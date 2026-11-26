"""Immutable, checksum-verified loader for one complete V2 release bundle."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from threading import Lock
from typing import Any, Optional

import torch

from app.domain.cells import BIOLOGICAL_CLASS_ORDER


class BundleValidationError(RuntimeError):
    """Raised when a release cannot be trusted as one coherent bundle."""


class ModelManager:
    REQUIRED_FILES = (
        "model.pt",
        "instance_classifier.pt",
        "model_manifest.json",
        "postprocess.json",
        "calibration.json",
        "class_map.json",
        "model_release_report.json",
        "model_release_report.md",
        "CHECKSUMS.sha256",
    )
    EXPECTED_OUTPUT_NAMES = (
        "np_logits",
        "hv_map",
        "nt_logits",
        "contour_logits",
        "seed_logits",
        "feature_map",
        "global_context",
    )
    _instances: dict[tuple[str, str], "ModelManager"] = {}
    _instances_lock = Lock()

    def __new__(
        cls,
        bundle_path: Optional[str | Path] = None,
        device: Optional[str] = None,
        *args,
        **kwargs,
    ):
        resolved = str(cls.resolve_bundle_path(bundle_path).resolve())
        resolved_device = device or os.getenv("TME_V2_DEVICE") or (
            "cuda" if torch.cuda.is_available() else "cpu"
        )
        key = (resolved, resolved_device)
        with cls._instances_lock:
            instance = cls._instances.get(key)
            if instance is None:
                instance = super().__new__(cls)
                cls._instances[key] = instance
        return instance

    def __init__(
        self,
        bundle_path: Optional[str | Path] = None,
        device: Optional[str] = None,
        *,
        validate_runtime: bool = True,
    ):
        if getattr(self, "_initialized", False):
            return
        self.bundle_path = self.resolve_bundle_path(bundle_path).resolve()
        self.device = torch.device(
            device
            or os.getenv("TME_V2_DEVICE")
            or ("cuda" if torch.cuda.is_available() else "cpu")
        )
        self._validate_files_present()
        self.checksums = self._read_checksums()
        self.verify_checksums()
        self.manifest = self._read_json("model_manifest.json")
        self.postprocess_config = self._read_json("postprocess.json")
        self.calibration_config = self._read_json("calibration.json")
        self.class_map = self._read_json("class_map.json")
        self.release_report = self._read_json("model_release_report.json")
        self._validate_configuration()

        try:
            self.model = torch.jit.load(
                str(self.bundle_path / self.manifest["checkpoint_file"]),
                map_location=self.device,
            )
            self.instance_classifier = torch.jit.load(
                str(self.bundle_path / self.manifest["instance_classifier_file"]),
                map_location=self.device,
            )
        except Exception as exc:
            raise BundleValidationError(f"TorchScript bundle load failed: {exc}") from exc
        self.model.eval()
        self.instance_classifier.eval()

        if validate_runtime:
            self.validate_runtime_contract()
        self._initialized = True

    @staticmethod
    def resolve_bundle_path(bundle_path: Optional[str | Path] = None) -> Path:
        if bundle_path:
            return Path(bundle_path)
        configured = os.getenv("TME_V2_BUNDLE_PATH")
        if configured:
            return Path(configured)
        return Path(__file__).resolve().parents[1] / "model_weights" / "tme_nuclei_v2"

    @classmethod
    def clear_cache(cls) -> None:
        """Test helper; production processes keep one manager per device."""
        with cls._instances_lock:
            cls._instances.clear()

    def _validate_files_present(self) -> None:
        missing = [name for name in self.REQUIRED_FILES if not (self.bundle_path / name).is_file()]
        if missing:
            raise BundleValidationError(
                f"Incomplete TME-Nuclei V2 bundle at {self.bundle_path}: {', '.join(missing)}"
            )

    def _read_json(self, filename: str) -> dict[str, Any]:
        try:
            with (self.bundle_path / filename).open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            raise BundleValidationError(f"Invalid {filename}: {exc}") from exc
        if not isinstance(payload, dict):
            raise BundleValidationError(f"{filename} must contain a JSON object")
        return payload

    def _read_checksums(self) -> dict[str, str]:
        checksums: dict[str, str] = {}
        try:
            lines = (self.bundle_path / "CHECKSUMS.sha256").read_text(
                encoding="utf-8"
            ).splitlines()
        except OSError as exc:
            raise BundleValidationError(f"Cannot read CHECKSUMS.sha256: {exc}") from exc
        for line in lines:
            if not line.strip():
                continue
            parts = line.split(maxsplit=1)
            if len(parts) != 2:
                raise BundleValidationError("Malformed CHECKSUMS.sha256 entry")
            digest, filename = parts
            filename = filename.lstrip("* ")
            if len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest.lower()):
                raise BundleValidationError(f"Malformed checksum for {filename}")
            checksums[filename] = digest.lower()
        expected = set(self.REQUIRED_FILES) - {"CHECKSUMS.sha256"}
        if set(checksums) != expected:
            missing = sorted(expected - set(checksums))
            extra = sorted(set(checksums) - expected)
            raise BundleValidationError(
                f"Checksum inventory mismatch; missing={missing}, extra={extra}"
            )
        return checksums

    def verify_checksums(self) -> None:
        for filename, expected in self.checksums.items():
            digest = hashlib.sha256()
            with (self.bundle_path / filename).open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
            actual = digest.hexdigest()
            if actual != expected:
                raise BundleValidationError(
                    f"Checksum mismatch for {filename}: expected {expected}, got {actual}"
                )

    def _validate_configuration(self) -> None:
        manifest = self.manifest
        if manifest.get("model_name") != "tme_nuclei_v2":
            raise BundleValidationError("Unexpected model_name")
        if manifest.get("model_version") != "2.0.0":
            raise BundleValidationError("Unexpected model_version")
        if manifest.get("framework") != "PyTorch/TorchScript":
            raise BundleValidationError("V2 requires PyTorch/TorchScript")
        if manifest.get("checkpoint_file") != "model.pt":
            raise BundleValidationError("Manifest checkpoint_file must be model.pt")
        if manifest.get("instance_classifier_file") != "instance_classifier.pt":
            raise BundleValidationError(
                "Manifest instance_classifier_file must be instance_classifier.pt"
            )
        if manifest.get("num_biological_classes") != 5:
            raise BundleValidationError("Exactly five biological classes are required")
        if tuple(manifest.get("class_order", ())) != BIOLOGICAL_CLASS_ORDER:
            raise BundleValidationError("Manifest biological class order is invalid")
        if tuple(manifest.get("input_patch_size", ())) != (256, 256):
            raise BundleValidationError("V2 input patch size must be 256x256")
        if tuple(manifest.get("output_tuple_order", ())) != self.EXPECTED_OUTPUT_NAMES:
            raise BundleValidationError("Dense output tuple order is invalid")

        normalization = manifest.get("normalization", {})
        if len(normalization.get("mean", ())) != 3 or len(normalization.get("std", ())) != 3:
            raise BundleValidationError("Normalization requires three means and stds")
        if any(float(std) <= 0 for std in normalization["std"]):
            raise BundleValidationError("Normalization std values must be positive")
        if manifest.get("stain_normalization", {}).get("required") is not False:
            raise BundleValidationError("Current V2 release must not require stain normalization")

        mapped = self.class_map.get("biological_classes", [])
        mapped_order = tuple(str(item.get("name", "")) for item in mapped)
        mapped_ids = tuple(item.get("id") for item in mapped)
        if mapped_order != BIOLOGICAL_CLASS_ORDER or mapped_ids != (1, 2, 3, 4, 5):
            raise BundleValidationError("class_map.json does not match the binding order")
        if not self.class_map.get("uncertain_is_application_state"):
            raise BundleValidationError("UNCERTAIN must be declared as an application state")

        required_postprocess = {
            "np_threshold",
            "seed_threshold",
            "min_nucleus_size",
            "marker_min_size",
            "hv_boundary_weight",
            "contour_weight",
            "morphology_open",
            "morphology_kernel",
            "instance_head_blend",
            "instance_descriptor",
        }
        if not required_postprocess.issubset(self.postprocess_config):
            raise BundleValidationError("postprocess.json is missing required fields")
        descriptor = self.postprocess_config["instance_descriptor"]
        if descriptor.get("descriptor_dim") != 132:
            raise BundleValidationError("Instance descriptor dimension must be 132")
        if not 0 <= float(self.postprocess_config["instance_head_blend"]) <= 1:
            raise BundleValidationError("instance_head_blend must be a probability")

        calibration = self.calibration_config
        if calibration.get("method") != "temperature_plus_class_bias":
            raise BundleValidationError("Unsupported calibration method")
        if float(calibration.get("temperature", 0)) <= 0:
            raise BundleValidationError("Calibration temperature must be positive")
        if len(calibration.get("class_bias", ())) != 5:
            raise BundleValidationError("Calibration requires five class biases")
        policy = calibration.get("acceptance_policy", {})
        if len(policy.get("per_class_min_confidence", {})) != 5:
            raise BundleValidationError("Acceptance policy requires five class thresholds")

    def validate_runtime_contract(self) -> None:
        patch_h, patch_w = self.patch_size
        with torch.inference_mode():
            dense = self.model(
                torch.zeros((1, 3, patch_h, patch_w), device=self.device)
            )
            classifier = self.instance_classifier(
                torch.zeros((1, self.descriptor_dim), device=self.device)
            )
        if not isinstance(dense, (tuple, list)) or len(dense) != 7:
            raise BundleValidationError("Dense model must return exactly seven outputs")
        expected = (
            (1, 2, patch_h, patch_w),
            (1, 2, patch_h, patch_w),
            (1, 5, patch_h, patch_w),
            (1, 1, patch_h, patch_w),
            (1, 1, patch_h, patch_w),
            (1, 32, patch_h, patch_w),
            (1, 64),
        )
        actual = tuple(tuple(tensor.shape) for tensor in dense)
        if actual != expected:
            raise BundleValidationError(
                f"Dense output shape mismatch: expected {expected}, got {actual}"
            )
        if tuple(classifier.shape) != (1, 5):
            raise BundleValidationError("Instance classifier output must be [B,5]")
        if not all(torch.isfinite(tensor).all() for tensor in (*dense, classifier)):
            raise BundleValidationError("Runtime validation produced NaN or Inf")

    @property
    def patch_size(self) -> tuple[int, int]:
        value = self.manifest["input_patch_size"]
        return int(value[0]), int(value[1])

    @property
    def expected_mpp(self) -> float:
        return float(self.manifest["expected_mpp"])

    @property
    def normalization(self) -> dict[str, Any]:
        return self.manifest["normalization"]

    @property
    def descriptor_dim(self) -> int:
        return int(self.postprocess_config["instance_descriptor"]["descriptor_dim"])

    @property
    def model_metadata(self) -> dict[str, Any]:
        return {
            "model_name": self.manifest["model_name"],
            "model_version": self.manifest["model_version"],
            "framework": self.manifest["framework"],
            "architecture": self.manifest["architecture"],
            "checkpoint_sha256": self.checksums["model.pt"],
            "class_order": tuple(self.manifest["class_order"]),
        }
