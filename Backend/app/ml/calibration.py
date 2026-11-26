"""Exact post-fusion temperature/class-bias calibration and abstention."""

from __future__ import annotations

from typing import Iterable, Sequence

import numpy as np

from app.domain.cells import AcceptanceStatus, BIOLOGICAL_CLASS_ORDER

from .postprocessing import LocalInstance


class ConfidenceCalibrator:
    def __init__(self, config: dict):
        if config.get("method") != "temperature_plus_class_bias":
            raise ValueError("Unsupported V2 calibration method")
        self.temperature = float(config["temperature"])
        self.class_bias = np.asarray(config["class_bias"], dtype=np.float64)
        self.policy = config["acceptance_policy"]
        if self.temperature <= 0 or self.class_bias.shape != (5,):
            raise ValueError("Invalid V2 calibration parameters")
        configured_thresholds = self.policy["per_class_min_confidence"]
        self.minimum_confidence = {
            name.upper(): float(threshold)
            for name, threshold in configured_thresholds.items()
        }
        if tuple(self.minimum_confidence) != BIOLOGICAL_CLASS_ORDER:
            raise ValueError("Acceptance thresholds do not follow the biological class order")
        self.max_entropy = float(self.policy["max_normalized_entropy"])
        self.min_margin = float(self.policy["min_top1_top2_margin"])

    def calibrate_vector(self, fused_probabilities: Sequence[float]) -> np.ndarray:
        probabilities = np.asarray(fused_probabilities, dtype=np.float64)
        if probabilities.shape != (5,) or not np.isfinite(probabilities).all():
            raise ValueError("Calibration input must be one finite five-class vector")
        if np.any(probabilities < 0) or probabilities.sum() <= 0:
            raise ValueError("Calibration probabilities must be non-negative and non-empty")
        probabilities = probabilities / probabilities.sum()
        logits = (np.log(np.clip(probabilities, 1e-8, 1.0)) + self.class_bias) / self.temperature
        logits -= logits.max()
        calibrated = np.exp(logits)
        return (calibrated / calibrated.sum()).astype(np.float32)

    def assess_probability_vector(
        self, calibrated: Sequence[float]
    ) -> tuple[int, str, float, float, float, AcceptanceStatus]:
        probabilities = np.asarray(calibrated, dtype=np.float64)
        if probabilities.shape != (5,) or not np.isfinite(probabilities).all():
            raise ValueError("Acceptance input must be a finite five-class vector")
        probabilities = probabilities / probabilities.sum()
        order = np.argsort(probabilities)[::-1]
        predicted_index = int(order[0])
        class_name = BIOLOGICAL_CLASS_ORDER[predicted_index]
        confidence = float(probabilities[predicted_index])
        entropy = float(
            -np.sum(probabilities * np.log(np.clip(probabilities, 1e-8, 1.0)))
            / np.log(5.0)
        )
        margin = float(probabilities[order[0]] - probabilities[order[1]])
        accepted = (
            confidence >= self.minimum_confidence[class_name]
            and entropy <= self.max_entropy
            and margin >= self.min_margin
        )
        return (
            predicted_index + 1,
            class_name,
            confidence,
            entropy,
            margin,
            AcceptanceStatus.ACCEPTED if accepted else AcceptanceStatus.UNCERTAIN,
        )

    def apply(self, instances: Iterable[LocalInstance]) -> list[LocalInstance]:
        calibrated_instances = list(instances)
        for instance in calibrated_instances:
            if instance.fused_probabilities is None:
                raise ValueError("Fusion must run before calibration")
            calibrated = self.calibrate_vector(instance.fused_probabilities)
            (
                instance.class_id,
                instance.class_name,
                instance.class_confidence,
                instance.normalized_entropy,
                instance.top1_top2_margin,
                instance.acceptance_status,
            ) = self.assess_probability_vector(calibrated)
            instance.calibrated_probabilities = calibrated
        return calibrated_instances
