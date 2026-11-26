import numpy as np
import pytest
import torch

from app.domain.cells import AcceptanceStatus
from app.ml.calibration import ConfidenceCalibrator
from app.ml.model_manager import ModelManager
from app.ml.postprocessing import InstancePostprocessor, LocalInstance
from app.ml.predictor import DenseOutputs
from app.ml.preprocessing import SourceTransform
from app.ml.stitching import InstanceStitcher
from app.ml.tiling import Tile


def synthetic_dense(seed_points):
    height = width = 256
    np_logits = torch.full((1, 2, height, width), -8.0)
    np_logits[:, 0] = 8.0
    yy, xx = np.ogrid[:height, :width]
    nucleus = (yy - 128) ** 2 / 18**2 + (xx - 120) ** 2 / 25**2 <= 1
    np_logits[0, 0, nucleus] = -8
    np_logits[0, 1, nucleus] = 8
    hv = torch.zeros((1, 2, height, width))
    nt = torch.zeros((1, 5, height, width))
    nt[:, 1] = 2.0
    contour = torch.full((1, 1, height, width), -8.0)
    seed = torch.full((1, 1, height, width), -8.0)
    for y, x in seed_points:
        seed[0, 0, y - 2 : y + 3, x - 2 : x + 3] = 8.0
    features = torch.arange(32, dtype=torch.float32).view(1, 32, 1, 1).expand(
        1, 32, height, width
    )
    context = torch.arange(64, dtype=torch.float32).view(1, 64)
    return DenseOutputs(
        np_logits,
        hv,
        nt,
        contour,
        seed,
        features,
        context,
        inference_ms=1,
        batch_size=1,
        device="cpu",
    )


def tile():
    return Tile(
        tile_id="tile-0-0",
        image=np.zeros((256, 256, 3), dtype=np.uint8),
        origin_x=0,
        origin_y=0,
        valid_width=256,
        valid_height=256,
        tissue_fraction=1,
    )


def test_isolated_nucleus_descriptor_and_classifier_contract():
    manager = ModelManager()
    processor = InstancePostprocessor(manager.postprocess_config)
    instances = processor.reconstruct(synthetic_dense([(128, 120)]), [tile()])
    assert len(instances) == 1
    assert instances[0].descriptor.shape == (132,)
    classified = processor.classify_and_fuse(
        instances, manager.instance_classifier, device=manager.device
    )
    assert classified[0].fused_probabilities.shape == (5,)
    assert classified[0].fused_probabilities.sum() == pytest.approx(1)


def test_two_learned_seeds_split_touching_foreground():
    manager = ModelManager()
    processor = InstancePostprocessor(manager.postprocess_config)
    instances = processor.reconstruct(
        synthetic_dense([(128, 110), (128, 130)]), [tile()]
    )
    assert len(instances) == 2


def test_weak_seed_uses_one_conservative_component_fallback():
    manager = ModelManager()
    processor = InstancePostprocessor(manager.postprocess_config)
    instances = processor.reconstruct(synthetic_dense([]), [tile()])
    assert len(instances) == 1


def test_calibration_applies_after_fusion_and_abstains():
    manager = ModelManager()
    calibrator = ConfidenceCalibrator(manager.calibration_config)
    accepted = calibrator.calibrate_vector([0.999, 0.00025, 0.00025, 0.00025, 0.00025])
    assessment = calibrator.assess_probability_vector(accepted)
    assert assessment[1] == "NEOPLASTIC"
    assert assessment[-1] == AcceptanceStatus.ACCEPTED
    uncertain = calibrator.calibrate_vector([0.22, 0.21, 0.20, 0.19, 0.18])
    assert calibrator.assess_probability_vector(uncertain)[-1] == AcceptanceStatus.UNCERTAIN


def local_instance(*, tile_id, origin_x, local_x, mask_x):
    mask = np.zeros((256, 256), dtype=bool)
    mask[100:111, mask_x : mask_x + 11] = True
    probability = np.asarray([0.98, 0.005, 0.005, 0.005, 0.005], dtype=np.float32)
    return LocalInstance(
        local_instance_id=f"{tile_id}-1",
        tile_id=tile_id,
        tile_origin_x=origin_x,
        tile_origin_y=0,
        tile_width=256,
        tile_height=256,
        mask=mask,
        centroid_x=local_x,
        centroid_y=105,
        area_px=121,
        bbox_xyxy=(mask_x, 100, mask_x + 10, 110),
        segmentation_confidence=0.9,
        descriptor=np.zeros(132, dtype=np.float32),
        pixel_probabilities=probability,
        fused_probabilities=probability,
        calibrated_probabilities=probability,
        class_id=1,
        class_name="NEOPLASTIC",
        class_confidence=0.98,
        normalized_entropy=0.05,
        top1_top2_margin=0.975,
        acceptance_status=AcceptanceStatus.ACCEPTED,
    )


def test_cross_tile_duplicate_becomes_one_global_cell():
    manager = ModelManager()
    stitcher = InstanceStitcher(ConfidenceCalibrator(manager.calibration_config))
    left = local_instance(tile_id="tile-0-0", origin_x=0, local_x=205, mask_x=200)
    right = local_instance(tile_id="tile-0-192", origin_x=192, local_x=13, mask_x=8)
    cells = stitcher.stitch(
        [left, right],
        source_transform=SourceTransform(
            scale_x=1,
            scale_y=1,
            source_mpp_x=0.25,
            source_mpp_y=0.25,
            trusted=True,
        ),
    )
    assert len(cells) == 1
    assert cells[0].source_tile_ids == ["tile-0-0", "tile-0-192"]
    assert cells[0].centroid_x_px == pytest.approx(205)
    assert cells[0].centroid_x_um == pytest.approx(51.25)


def test_nearby_distinct_nuclei_remain_two():
    manager = ModelManager()
    stitcher = InstanceStitcher(ConfidenceCalibrator(manager.calibration_config))
    left = local_instance(tile_id="tile-0-0", origin_x=0, local_x=205, mask_x=200)
    right = local_instance(tile_id="tile-0-192", origin_x=192, local_x=28, mask_x=23)
    cells = stitcher.stitch([left, right], source_transform=SourceTransform())
    assert len(cells) == 2
