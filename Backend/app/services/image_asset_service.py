"""Unchanged source-image persistence and metadata extraction."""

from __future__ import annotations

import hashlib
import io
import json
import mimetypes
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from uuid import uuid4

import cv2
import numpy as np
import tifffile

from app.domain.image_metadata import ImageMetadata
from app.ml.preprocessing import ScaleResolution


@dataclass(frozen=True)
class PersistedImageAsset:
    metadata: ImageMetadata
    source_path: Path
    metadata_path: Path
    preview_path: Path
    image_rgb: np.ndarray
    scanner_metadata: dict[str, object]


class ImageAssetService:
    def __init__(self, storage_root: Optional[str | Path] = None):
        configured = storage_root or os.getenv("TME_ANALYSIS_STORAGE_ROOT")
        self.storage_root = Path(configured) if configured else (
            Path(__file__).resolve().parents[1] / "analysis_storage"
        )

    @staticmethod
    def decode(source_bytes: bytes) -> np.ndarray:
        encoded = np.frombuffer(source_bytes, dtype=np.uint8)
        bgr = cv2.imdecode(encoded, cv2.IMREAD_UNCHANGED)
        if bgr is None:
            raise ValueError("IMAGE_DECODE_FAILED")
        if bgr.ndim == 2:
            bgr = cv2.cvtColor(bgr, cv2.COLOR_GRAY2BGR)
        if bgr.ndim != 3 or bgr.shape[2] not in (3, 4):
            raise ValueError("UNSUPPORTED_CHANNELS")
        if bgr.shape[2] == 4:
            bgr = cv2.cvtColor(bgr, cv2.COLOR_BGRA2BGR)
        return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

    @staticmethod
    def extract_scanner_metadata(source_bytes: bytes) -> dict[str, object]:
        metadata: dict[str, object] = {}
        try:
            with tifffile.TiffFile(io.BytesIO(source_bytes)) as tif:
                if not tif.pages:
                    return metadata
                page = tif.pages[0]
                unit_tag = page.tags.get("ResolutionUnit")
                unit = int(unit_tag.value) if unit_tag else 1
                for axis, tag_name in (("x", "XResolution"), ("y", "YResolution")):
                    tag = page.tags.get(tag_name)
                    if not tag:
                        continue
                    numerator, denominator = tag.value
                    pixels_per_unit = float(numerator) / float(denominator)
                    if pixels_per_unit <= 0:
                        continue
                    if unit == 2:  # inch
                        metadata[f"tiff.mpp-{axis}"] = 25400.0 / pixels_per_unit
                    elif unit == 3:  # centimetre
                        metadata[f"tiff.mpp-{axis}"] = 10000.0 / pixels_per_unit
                description = (page.description or "").lower()
                match = re.search(r"(?:magnification|objective)[^0-9]*(\d+(?:\.\d+)?)\s*x?", description)
                if match:
                    metadata["magnification"] = float(match.group(1))
                scanner = re.search(r"(?:scanner|model)\s*[:=]\s*([^;\n]+)", description)
                if scanner:
                    metadata["scanner"] = scanner.group(1).strip()
        except Exception:
            # Non-TIFF uploads legitimately do not have scanner metadata.
            return metadata
        return metadata

    def persist(
        self,
        *,
        source_bytes: bytes,
        filename: str,
        mime_type: Optional[str],
        patient_id: str,
        session_id: str,
        scale: ScaleResolution,
        asset_id: Optional[str] = None,
    ) -> PersistedImageAsset:
        image_rgb = self.decode(source_bytes)
        scanner_metadata = self.extract_scanner_metadata(source_bytes)
        asset_id = asset_id or str(uuid4())
        suffix = Path(filename).suffix.lower()
        if not suffix or not re.fullmatch(r"\.[a-z0-9]{1,8}", suffix):
            suffix = mimetypes.guess_extension(mime_type or "") or ".img"
        destination = self.storage_root / "analysis-source" / patient_id / session_id
        destination.mkdir(parents=True, exist_ok=True)
        source_path = destination / f"source{suffix}"
        checksum = hashlib.sha256(source_bytes).hexdigest()
        # Retrying the same immutable upload is safe. A different payload for
        # an existing session remains forbidden, even if its extension differs.
        existing_sources = sorted(destination.glob("source.*"))
        if existing_sources:
            existing_source = existing_sources[0]
            existing_checksum = hashlib.sha256(existing_source.read_bytes()).hexdigest()
            if existing_checksum != checksum:
                raise FileExistsError("session already has a different source image")
            source_path = existing_source
        else:
            with source_path.open("xb") as handle:
                handle.write(source_bytes)
        preview_path = destination / "preview.jpg"
        preview = image_rgb
        maximum = 1024
        if max(preview.shape[:2]) > maximum:
            ratio = maximum / max(preview.shape[:2])
            preview = cv2.resize(
                preview,
                (int(round(preview.shape[1] * ratio)), int(round(preview.shape[0] * ratio))),
                interpolation=cv2.INTER_AREA,
            )
        ok, preview_bytes = cv2.imencode(
            ".jpg", cv2.cvtColor(preview, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, 88]
        )
        if not ok:
            raise RuntimeError("PREVIEW_ENCODING_FAILED")
        preview_path.write_bytes(preview_bytes.tobytes())

        metadata = ImageMetadata(
            asset_id=asset_id,
            original_filename=Path(filename).name,
            mime_type=mime_type or mimetypes.guess_type(filename)[0] or "application/octet-stream",
            width_px=int(image_rgb.shape[1]),
            height_px=int(image_rgb.shape[0]),
            channels=int(image_rgb.shape[2]),
            bit_depth=int(image_rgb.dtype.itemsize * 8),
            scanner=str(scanner_metadata.get("scanner")) if scanner_metadata.get("scanner") else None,
            source_mpp_x=scale.source_mpp_x,
            source_mpp_y=scale.source_mpp_y,
            source_magnification=scale.source_magnification,
            effective_mpp_x=scale.source_mpp_x if scale.trusted else None,
            effective_mpp_y=scale.source_mpp_y if scale.trusted else None,
            effective_magnification=scale.source_magnification if scale.trusted else None,
            scale_source=scale.scale_source,
            scale_trusted=scale.trusted,
            checksum_sha256=checksum,
        )
        metadata_path = destination / "metadata.json"
        metadata_path.write_text(
            json.dumps(metadata.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )
        return PersistedImageAsset(
            metadata=metadata,
            source_path=source_path,
            metadata_path=metadata_path,
            preview_path=preview_path,
            image_rgb=image_rgb,
            scanner_metadata=scanner_metadata,
        )

    def load(self, metadata: ImageMetadata, storage_path: str | Path) -> PersistedImageAsset:
        source_path = Path(storage_path).resolve()
        storage_root = self.storage_root.resolve()
        if storage_root not in source_path.parents or not source_path.is_file():
            raise FileNotFoundError("Image asset is outside the configured storage root")
        source_bytes = source_path.read_bytes()
        checksum = hashlib.sha256(source_bytes).hexdigest()
        if checksum != metadata.checksum_sha256:
            raise ValueError("SOURCE_IMAGE_CHECKSUM_MISMATCH")
        destination = source_path.parent
        return PersistedImageAsset(
            metadata=metadata,
            source_path=source_path,
            metadata_path=destination / "metadata.json",
            preview_path=destination / "preview.jpg",
            image_rgb=self.decode(source_bytes),
            scanner_metadata=self.extract_scanner_metadata(source_bytes),
        )
