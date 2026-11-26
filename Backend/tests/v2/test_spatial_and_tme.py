from datetime import datetime, timezone

from app.domain import (
    AcceptanceStatus,
    CellInstance,
    ImageMetadata,
    QualityAssessment,
    QualityStatus,
    ScaleSource,
    TMEState,
)
from app.domain.tumor import TumorRegionMode
from app.services.spatial_engine import SpatialEngine
from app.services.tme_policy import TMEPolicyV1
from app.services.tumor_context_service import TumorContextService


def cell(instance_id, class_id, name, x_um, y_um, acceptance=AcceptanceStatus.ACCEPTED):
    probabilities = [0.01] * 5
    probabilities[class_id - 1] = 0.96
    return CellInstance(
        instance_id=instance_id,
        class_id=class_id,
        class_name=name,
        centroid_x_px=x_um / 0.25,
        centroid_y_px=y_um / 0.25,
        centroid_x_um=x_um,
        centroid_y_um=y_um,
        area_px=20,
        area_um2=1.25,
        bbox_xyxy=(0, 0, 2, 2),
        class_probabilities=tuple(probabilities),
        class_confidence=0.96,
        normalized_entropy=0.1,
        top1_top2_margin=0.95,
        acceptance_status=acceptance,
        source_tile_ids=["tile"],
    )


def metadata(trusted=True):
    return ImageMetadata(
        asset_id="asset",
        original_filename="source.png",
        mime_type="image/png",
        width_px=1000,
        height_px=1000,
        channels=3,
        source_mpp_x=0.25 if trusted else None,
        source_mpp_y=0.25 if trusted else None,
        effective_mpp_x=0.25 if trusted else None,
        effective_mpp_y=0.25 if trusted else None,
        scale_source=ScaleSource.USER_PROVIDED if trusted else ScaleSource.UNKNOWN,
        scale_trusted=trusted,
        checksum_sha256="a" * 64,
    )


def quality(scale=True):
    return QualityAssessment(
        status=QualityStatus.PASS,
        tissue_fraction=1,
        background_fraction=0,
        resolution_valid=True,
        scale_valid=scale,
    )


def test_spatial_engine_uses_accepted_physical_cells_only():
    tumor = TumorContextService.clinician_confirmed(
        present=True, user_id="user", region_mode=TumorRegionMode.WHOLE_ROI
    )
    cells = [
        cell("n1", 1, "NEOPLASTIC", 10, 10),
        cell("n2", 1, "NEOPLASTIC", 20, 10),
        cell("i1", 2, "INFLAMMATORY", 15, 10),
        cell("i2", 2, "INFLAMMATORY", 500, 500, AcceptanceStatus.UNCERTAIN),
    ]
    result = SpatialEngine().measure(
        cells=cells,
        tumor=tumor,
        metadata=metadata(),
        tissue_area_px=1_000_000,
    )
    assert result.neo_count_accepted == 2
    assert result.immune_count_accepted == 1
    assert result.class_counts_uncertain["INFLAMMATORY"] == 1
    assert result.neo_to_immune_mean_um == 5
    assert result.tissue_area_mm2 == 0.0625


def test_policy_keeps_unknown_scale_not_assessable():
    tumor = TumorContextService.clinician_confirmed(present=True, user_id="user")
    result = TMEPolicyV1().evaluate(
        spatial=None,
        tumor=tumor,
        quality=quality(scale=False),
        metadata=metadata(trusted=False),
    )
    assert result.state == TMEState.NOT_ASSESSABLE.value
    assert result.reason_codes == ["PHYSICAL_SCALE_UNKNOWN"]


def test_no_tumor_is_not_applicable_not_cold():
    tumor = TumorContextService.clinician_confirmed(present=False, user_id="user")
    result = TMEPolicyV1().evaluate(
        spatial=None,
        tumor=tumor,
        quality=quality(),
        metadata=metadata(),
    )
    assert result.state == TMEState.NOT_APPLICABLE.value


def test_tumor_with_insufficient_immune_evidence_is_indeterminate():
    tumor = TumorContextService.clinician_confirmed(present=True, user_id="user")
    spatial = SpatialEngine().measure(
        cells=[cell("n1", 1, "NEOPLASTIC", 10, 10)],
        tumor=tumor,
        metadata=metadata(),
        tissue_area_px=1_000_000,
    )
    result = TMEPolicyV1().evaluate(
        spatial=spatial,
        tumor=tumor,
        quality=quality(),
        metadata=metadata(),
    )
    assert result.state == TMEState.INDETERMINATE.value
    assert "INSUFFICIENT_ACCEPTED_NEOPLASTIC_EVIDENCE" in result.reason_codes
