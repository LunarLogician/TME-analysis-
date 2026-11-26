"""Scale resolution, resampling, normalization, and coordinate transforms."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Optional

import cv2
import numpy as np
import torch

from app.domain.image_metadata import ScaleSource


@dataclass(frozen=True)
class ScaleResolution:
    source_mpp_x: Optional[float]
    source_mpp_y: Optional[float]
    source_magnification: Optional[float]
    scale_source: ScaleSource
    trusted: bool


@dataclass(frozen=True)
class SourceTransform:
    """Round-trippable transforms among resampled, source, and physical space."""

    scale_x: float = 1.0
    scale_y: float = 1.0
    source_mpp_x: Optional[float] = None
    source_mpp_y: Optional[float] = None
    trusted: bool = False

    def resampled_to_source(self, x: float, y: float) -> tuple[float, float]:
        return x / self.scale_x, y / self.scale_y

    def source_to_resampled(self, x: float, y: float) -> tuple[float, float]:
        return x * self.scale_x, y * self.scale_y

    def source_to_physical(self, x: float, y: float) -> tuple[Optional[float], Optional[float]]:
        if not self.trusted or self.source_mpp_x is None or self.source_mpp_y is None:
            return None, None
        return x * self.source_mpp_x, y * self.source_mpp_y

    def resampled_to_physical(
        self, x: float, y: float
    ) -> tuple[Optional[float], Optional[float]]:
        source_x, source_y = self.resampled_to_source(x, y)
        return self.source_to_physical(source_x, source_y)


class ScaleResolver:
    """Resolve scale in the mandated priority order without a trusted fallback."""

    def __init__(self, magnification_policy: Optional[Mapping[float, float]] = None):
        self.magnification_policy = dict(magnification_policy or {})

    @staticmethod
    def _positive(value) -> Optional[float]:
        try:
            parsed = float(value)
        except (TypeError, ValueError):
            return None
        return parsed if np.isfinite(parsed) and parsed > 0 else None

    def resolve(
        self,
        metadata: Mapping[str, object],
        *,
        user_mpp_x: Optional[float] = None,
        user_mpp_y: Optional[float] = None,
        user_magnification: Optional[float] = None,
    ) -> ScaleResolution:
        # Reliable WSI metadata.
        wsi_x = self._positive(metadata.get("openslide.mpp-x"))
        wsi_y = self._positive(metadata.get("openslide.mpp-y")) or wsi_x
        if wsi_x and wsi_y:
            return ScaleResolution(
                wsi_x,
                wsi_y,
                self._positive(metadata.get("openslide.objective-power")),
                ScaleSource.WSI_METADATA,
                True,
            )

        # TIFF/scanner metadata must already be converted to micrometres/pixel.
        tiff_x = self._positive(metadata.get("tiff.mpp-x"))
        tiff_y = self._positive(metadata.get("tiff.mpp-y")) or tiff_x
        if tiff_x and tiff_y:
            return ScaleResolution(
                tiff_x,
                tiff_y,
                self._positive(metadata.get("magnification")),
                ScaleSource.TIFF_METADATA,
                True,
            )

        provided_x = self._positive(user_mpp_x)
        provided_y = self._positive(user_mpp_y) or provided_x
        if provided_x and provided_y:
            return ScaleResolution(
                provided_x,
                provided_y,
                self._positive(user_magnification),
                ScaleSource.USER_PROVIDED,
                True,
            )

        magnification = self._positive(user_magnification) or self._positive(
            metadata.get("magnification")
        )
        if magnification in self.magnification_policy:
            mapped_mpp = self._positive(self.magnification_policy[magnification])
            if mapped_mpp:
                return ScaleResolution(
                    mapped_mpp,
                    mapped_mpp,
                    magnification,
                    ScaleSource.MAGNIFICATION_POLICY,
                    True,
                )

        return ScaleResolution(None, None, magnification, ScaleSource.UNKNOWN, False)


def resample_to_model_scale(
    image: np.ndarray,
    scale: ScaleResolution,
    target_mpp: float,
) -> tuple[np.ndarray, SourceTransform]:
    if not scale.trusted or scale.source_mpp_x is None or scale.source_mpp_y is None:
        return image, SourceTransform()
    scale_x = scale.source_mpp_x / float(target_mpp)
    scale_y = scale.source_mpp_y / float(target_mpp)
    width = max(1, int(round(image.shape[1] * scale_x)))
    height = max(1, int(round(image.shape[0] * scale_y)))
    interpolation = cv2.INTER_LINEAR if max(scale_x, scale_y) > 1 else cv2.INTER_AREA
    resampled = cv2.resize(image, (width, height), interpolation=interpolation)
    return resampled, SourceTransform(
        scale_x=scale_x,
        scale_y=scale_y,
        source_mpp_x=scale.source_mpp_x,
        source_mpp_y=scale.source_mpp_y,
        trusted=True,
    )


def normalize_rgb_batch(images: list[np.ndarray], normalization: Mapping[str, object]) -> torch.Tensor:
    if not images:
        raise ValueError("At least one RGB tile is required")
    arrays = []
    for image in images:
        if image.ndim != 3 or image.shape[2] != 3:
            raise ValueError("V2 preprocessing requires RGB HxWx3 tiles")
        arrays.append(image.astype(np.float32) / 255.0)
    batch = np.stack(arrays, axis=0)
    mean = np.asarray(normalization["mean"], dtype=np.float32).reshape(1, 1, 1, 3)
    std = np.asarray(normalization["std"], dtype=np.float32).reshape(1, 1, 1, 3)
    normalized = (batch - mean) / std
    return torch.from_numpy(normalized.transpose(0, 3, 1, 2)).contiguous()
