import cv2
import numpy as np
from skimage import data

from app.domain.quality import QualityStatus
from app.services.quality_service import QualityController


def synthetic_he_patch(seed: int = 7) -> np.ndarray:
    """Create a repeatable pink tissue field with purple nuclear texture."""
    rng = np.random.default_rng(seed)
    image = np.full((256, 256, 3), (239, 196, 215), dtype=np.uint8)
    for _ in range(75):
        center = tuple(int(value) for value in rng.integers(0, 256, 2))
        axes = tuple(int(value) for value in rng.integers(8, 28, 2))
        cv2.ellipse(
            image,
            center,
            axes,
            int(rng.integers(0, 180)),
            0,
            360,
            (222, 155, 191),
            -1,
        )
    for _ in range(500):
        center = tuple(int(value) for value in rng.integers(0, 256, 2))
        cv2.circle(image, center, int(rng.integers(2, 5)), (89, 55, 132), -1)
    noise = rng.normal(0, 5, image.shape)
    return np.clip(image.astype(float) + noise, 0, 255).astype(np.uint8)


def test_he_patch_passes_automatic_stain_gate():
    result = QualityController().assess(synthetic_he_patch(), scale_valid=True)

    assert result.status == QualityStatus.PASS.value
    assert result.he_stain_valid is True
    assert result.he_stain_score is not None and result.he_stain_score >= 0.8
    assert "UNSUPPORTED_NON_HE_IMAGE" not in result.failures


def test_natural_photo_is_rejected_without_manual_override():
    result = QualityController().assess(data.chelsea(), scale_valid=True)

    assert result.status == QualityStatus.FAIL.value
    assert result.he_stain_valid is False
    assert "UNSUPPORTED_NON_HE_IMAGE" in result.failures


def test_grayscale_image_is_rejected():
    grayscale_rgb = np.repeat(data.camera()[:, :, None], 3, axis=2)
    result = QualityController().assess(grayscale_rgb, scale_valid=True)

    assert result.he_stain_valid is False
    assert result.chromatic_tissue_fraction == 0
    assert "UNSUPPORTED_NON_HE_IMAGE" in result.failures


def test_non_he_immunohistochemistry_is_rejected():
    result = QualityController().assess(
        data.immunohistochemistry(),
        scale_valid=True,
    )

    assert result.he_stain_valid is False
    assert "UNSUPPORTED_NON_HE_IMAGE" in result.failures
