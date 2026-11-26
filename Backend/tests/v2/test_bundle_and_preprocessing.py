from pathlib import Path

import numpy as np
import pytest

from app.domain.image_metadata import ScaleSource
from app.ml.model_manager import BundleValidationError, ModelManager
from app.ml.preprocessing import ScaleResolver, normalize_rgb_batch, resample_to_model_scale
from app.ml.tiling import TileGenerator


def test_deployed_bundle_loads_and_validates_exact_runtime_contract():
    manager = ModelManager()
    assert manager.manifest["class_order"] == [
        "NEOPLASTIC",
        "INFLAMMATORY",
        "CONNECTIVE",
        "DEAD",
        "EPITHELIAL",
    ]
    assert manager.patch_size == (256, 256)
    assert manager.descriptor_dim == 132


def test_checksum_corruption_fails_readiness(tmp_path):
    source = ModelManager.resolve_bundle_path()
    for path in source.iterdir():
        if path.name.endswith(".pt"):
            # A missing binary fails before any large copy is necessary.
            continue
        (tmp_path / path.name).write_bytes(path.read_bytes())
    (tmp_path / "model.pt").write_bytes(b"corrupt")
    (tmp_path / "instance_classifier.pt").write_bytes(b"corrupt")
    ModelManager.clear_cache()
    with pytest.raises(BundleValidationError, match="Checksum mismatch"):
        ModelManager(tmp_path)
    ModelManager.clear_cache()


def test_unknown_scale_never_becomes_trusted_fallback():
    scale = ScaleResolver().resolve({})
    assert scale.trusted is False
    assert scale.scale_source == ScaleSource.UNKNOWN
    assert scale.source_mpp_x is None


def test_scale_priority_and_physical_resampling():
    resolver = ScaleResolver({20.0: 0.5})
    scale = resolver.resolve(
        {"openslide.mpp-x": 0.4, "openslide.mpp-y": 0.5},
        user_mpp_x=0.7,
        user_mpp_y=0.7,
    )
    assert scale.scale_source == ScaleSource.WSI_METADATA
    image = np.zeros((10, 20, 3), dtype=np.uint8)
    resampled, transform = resample_to_model_scale(image, scale, target_mpp=0.25)
    assert resampled.shape == (20, 32, 3)
    assert transform.resampled_to_source(16, 10) == pytest.approx((10, 5))
    assert transform.resampled_to_physical(16, 10) == pytest.approx((4, 2.5))


def test_normalization_uses_manifest_values():
    manager = ModelManager()
    image = np.full((256, 256, 3), 255, dtype=np.uint8)
    tensor = normalize_rgb_batch([image], manager.normalization)
    expected = (1.0 - np.asarray(manager.normalization["mean"])) / np.asarray(
        manager.normalization["std"]
    )
    assert tensor.shape == (1, 3, 256, 256)
    assert tensor[0, :, 0, 0].numpy() == pytest.approx(expected)


def test_overlapping_tiler_preserves_full_field_and_padding():
    image = np.zeros((300, 400, 3), dtype=np.uint8)
    tissue = np.ones((300, 400), dtype=bool)
    tiles = TileGenerator((256, 256), overlap=64).generate(image, tissue)
    assert {(tile.origin_x, tile.origin_y) for tile in tiles} == {
        (0, 0),
        (144, 0),
        (0, 44),
        (144, 44),
    }
    assert all(tile.image.shape == (256, 256, 3) for tile in tiles)


def test_tiler_skips_background_only_tiles():
    image = np.full((256, 512, 3), 255, dtype=np.uint8)
    tissue = np.zeros((256, 512), dtype=bool)
    tissue[:, :256] = True
    tiles = TileGenerator((256, 256), overlap=0, minimum_tissue_fraction=0.1).generate(
        image, tissue
    )
    assert [tile.origin_x for tile in tiles] == [0]
