"""Decode-level image QC, H&E compatibility screening, and tissue masking."""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from skimage.color import rgb2hed

from app.domain.quality import QualityAssessment, QualityStatus


@dataclass(frozen=True)
class QualityPolicy:
    minimum_dimension_px: int = 64
    minimum_tissue_fraction: float = 0.01
    warning_blur_variance: float = 35.0
    failure_blur_variance: float = 5.0
    warning_extreme_exposure_fraction: float = 0.35
    failure_extreme_exposure_fraction: float = 0.80
    he_evaluation_max_dimension_px: int = 512
    he_chromatic_saturation: int = 12
    minimum_chromatic_tissue_fraction: float = 0.05
    minimum_stain_hue_fraction: float = 0.20
    minimum_hematoxylin_fraction: float = 0.15
    maximum_non_he_stain_mean: float = 0.10


@dataclass(frozen=True)
class HEPlausibilityAssessment:
    """Deterministic compatibility result; this is not a diagnostic classifier."""

    valid: bool
    score: float
    hematoxylin_fraction: float
    eosin_fraction: float
    stain_hue_fraction: float
    chromatic_tissue_fraction: float
    non_he_stain_mean: float


def compute_tissue_mask(image_rgb: np.ndarray) -> np.ndarray:
    if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        raise ValueError("Tissue masking requires an RGB image")
    hsv = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2HSV)
    gray = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2GRAY)
    saturation = hsv[:, :, 1]
    # Tissue is normally either chromatic or sufficiently darker than the slide
    # background. This mask is a deployment skip/QC mask, not a diagnostic model.
    tissue = (saturation > 18) | (gray < 225)
    tissue = cv2.morphologyEx(
        tissue.astype(np.uint8),
        cv2.MORPH_CLOSE,
        np.ones((5, 5), dtype=np.uint8),
    )
    return tissue.astype(bool)


class QualityController:
    def __init__(self, policy: QualityPolicy | None = None):
        self.policy = policy or QualityPolicy()

    def assess_he_compatibility(
        self,
        image_rgb: np.ndarray,
    ) -> HEPlausibilityAssessment:
        """Screen for an H&E-like stain profile without invoking a remote model.

        The gate combines HED colour deconvolution with a magenta/purple hue
        check. The latter prevents blue/grey natural photographs from passing
        on hematoxylin-like optical density alone. Eosin is retained as an
        audit metric but is not mandatory because lightly stained H&E patches
        can contain very little measurable eosin.
        """
        if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
            return HEPlausibilityAssessment(False, 0, 0, 0, 0, 0, 1)

        evaluation_image = image_rgb
        maximum = self.policy.he_evaluation_max_dimension_px
        largest_dimension = max(evaluation_image.shape[:2])
        if largest_dimension > maximum:
            ratio = maximum / largest_dimension
            evaluation_image = cv2.resize(
                evaluation_image,
                None,
                fx=ratio,
                fy=ratio,
                interpolation=cv2.INTER_AREA,
            )

        tissue_mask = compute_tissue_mask(evaluation_image)
        if not tissue_mask.any():
            return HEPlausibilityAssessment(False, 0, 0, 0, 0, 0, 1)

        hsv = cv2.cvtColor(evaluation_image, cv2.COLOR_RGB2HSV)
        tissue_saturation = hsv[:, :, 1][tissue_mask]
        chromatic = tissue_saturation > self.policy.he_chromatic_saturation
        chromatic_tissue_fraction = float(chromatic.mean())

        if chromatic.any():
            chromatic_hues = hsv[:, :, 0][tissue_mask][chromatic]
            # OpenCV hue is [0, 179]. H&E nuclei and eosin-rich tissue are
            # expected to occupy the purple-to-magenta range.
            stain_hue_fraction = float(np.mean(chromatic_hues >= 125))
        else:
            stain_hue_fraction = 0.0

        hed_tissue = rgb2hed(evaluation_image)[tissue_mask]
        hematoxylin_fraction = float(np.mean(hed_tissue[:, 0] > 0.02))
        eosin_fraction = float(np.mean(hed_tissue[:, 1] > 0.002))
        non_he_stain_mean = float(np.mean(np.clip(hed_tissue[:, 2], 0, None)))

        chromatic_score = min(
            1.0,
            chromatic_tissue_fraction
            / self.policy.minimum_chromatic_tissue_fraction,
        )
        hue_score = min(
            1.0,
            stain_hue_fraction / self.policy.minimum_stain_hue_fraction,
        )
        hematoxylin_score = min(
            1.0,
            hematoxylin_fraction / self.policy.minimum_hematoxylin_fraction,
        )
        non_he_score = max(
            0.0,
            1.0
            - non_he_stain_mean / self.policy.maximum_non_he_stain_mean,
        )
        score = float(
            np.clip(
                0.20 * chromatic_score
                + 0.35 * hue_score
                + 0.35 * hematoxylin_score
                + 0.10 * non_he_score,
                0,
                1,
            )
        )
        valid = (
            chromatic_tissue_fraction
            >= self.policy.minimum_chromatic_tissue_fraction
            and stain_hue_fraction >= self.policy.minimum_stain_hue_fraction
            and hematoxylin_fraction >= self.policy.minimum_hematoxylin_fraction
            and non_he_stain_mean <= self.policy.maximum_non_he_stain_mean
        )
        return HEPlausibilityAssessment(
            valid=valid,
            score=score,
            hematoxylin_fraction=hematoxylin_fraction,
            eosin_fraction=eosin_fraction,
            stain_hue_fraction=stain_hue_fraction,
            chromatic_tissue_fraction=chromatic_tissue_fraction,
            non_he_stain_mean=non_he_stain_mean,
        )

    def assess(self, image_rgb: np.ndarray, *, scale_valid: bool) -> QualityAssessment:
        failures: list[str] = []
        warnings: list[str] = []
        if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
            return QualityAssessment(
                status=QualityStatus.FAIL,
                tissue_fraction=0,
                background_fraction=1,
                resolution_valid=False,
                scale_valid=scale_valid,
                he_stain_valid=False,
                he_stain_score=0,
                failures=["UNSUPPORTED_CHANNELS"],
            )
        height, width = image_rgb.shape[:2]
        resolution_valid = min(height, width) >= self.policy.minimum_dimension_px
        if not resolution_valid:
            failures.append("IMAGE_DIMENSIONS_TOO_SMALL")

        tissue_mask = compute_tissue_mask(image_rgb)
        tissue_fraction = float(tissue_mask.mean())
        background_fraction = 1.0 - tissue_fraction
        if tissue_fraction < self.policy.minimum_tissue_fraction:
            failures.append("INSUFFICIENT_TISSUE")

        he_assessment = self.assess_he_compatibility(image_rgb)
        if not he_assessment.valid:
            failures.append("UNSUPPORTED_NON_HE_IMAGE")

        gray = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2GRAY)
        blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        if blur_score < self.policy.failure_blur_variance:
            failures.append("GROSS_BLUR")
        elif blur_score < self.policy.warning_blur_variance:
            warnings.append("POSSIBLE_BLUR")

        extreme_exposure = float(np.mean((gray <= 5) | (gray >= 250)))
        if extreme_exposure > self.policy.failure_extreme_exposure_fraction:
            failures.append("GROSS_EXPOSURE")
        elif extreme_exposure > self.policy.warning_extreme_exposure_fraction:
            warnings.append("POSSIBLE_EXPOSURE_ISSUE")

        if not scale_valid:
            warnings.append("PHYSICAL_SCALE_UNKNOWN")
        status = (
            QualityStatus.FAIL
            if failures
            else QualityStatus.WARNING
            if warnings
            else QualityStatus.PASS
        )
        return QualityAssessment(
            status=status,
            blur_score=blur_score,
            tissue_fraction=tissue_fraction,
            background_fraction=background_fraction,
            exposure_score=extreme_exposure,
            resolution_valid=resolution_valid,
            scale_valid=scale_valid,
            he_stain_valid=he_assessment.valid,
            he_stain_score=he_assessment.score,
            hematoxylin_fraction=he_assessment.hematoxylin_fraction,
            eosin_fraction=he_assessment.eosin_fraction,
            stain_hue_fraction=he_assessment.stain_hue_fraction,
            chromatic_tissue_fraction=he_assessment.chromatic_tissue_fraction,
            warnings=warnings,
            failures=failures,
        )
