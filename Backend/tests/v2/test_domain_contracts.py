from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.domain import (
    AcceptanceStatus,
    AnalysisOutput,
    AnalysisStatus,
    CellInstance,
    ImageMetadata,
    ModelMetadata,
    QualityAssessment,
    QualityStatus,
    ScaleSource,
    TMEAssessment,
    TMEState,
    TumorAssessment,
    TumorEvidenceSource,
    TumorRegionMode,
    TumorStatus,
)


def cell(**changes):
    payload = {
        "instance_id": "cell-1",
        "class_id": 1,
        "class_name": "NEOPLASTIC",
        "centroid_x_px": 10,
        "centroid_y_px": 20,
        "area_px": 20,
        "bbox_xyxy": (8, 18, 12, 22),
        "class_probabilities": (0.96, 0.01, 0.01, 0.01, 0.01),
        "class_confidence": 0.96,
        "normalized_entropy": 0.10,
        "top1_top2_margin": 0.95,
        "acceptance_status": AcceptanceStatus.ACCEPTED,
        "source_tile_ids": ["tile-0-0"],
    }
    payload.update(changes)
    return CellInstance(**payload)


def metadata(*, trusted=False):
    return ImageMetadata(
        asset_id="asset",
        original_filename="slide.png",
        mime_type="image/png",
        width_px=256,
        height_px=256,
        channels=3,
        source_mpp_x=0.25 if trusted else None,
        source_mpp_y=0.25 if trusted else None,
        effective_mpp_x=0.25 if trusted else None,
        effective_mpp_y=0.25 if trusted else None,
        scale_source=ScaleSource.USER_PROVIDED if trusted else ScaleSource.UNKNOWN,
        scale_trusted=trusted,
        checksum_sha256="a" * 64,
    )


def quality(*, scale_valid=False):
    return QualityAssessment(
        status=QualityStatus.WARNING,
        tissue_fraction=0.5,
        background_fraction=0.5,
        resolution_valid=True,
        scale_valid=scale_valid,
        warnings=[] if scale_valid else ["PHYSICAL_SCALE_UNKNOWN"],
    )


def model_metadata():
    return ModelMetadata(
        model_name="tme_nuclei_v2",
        model_version="2.0.0",
        framework="PyTorch/TorchScript",
        architecture="test",
        checkpoint_sha256="b" * 64,
        class_order=(
            "NEOPLASTIC",
            "INFLAMMATORY",
            "CONNECTIVE",
            "DEAD",
            "EPITHELIAL",
        ),
    )


def unconfirmed():
    return TumorAssessment(
        status=TumorStatus.INDETERMINATE,
        evidence_source=TumorEvidenceSource.UNCONFIRMED_NUCLEI_ONLY,
        tumor_region_mode=TumorRegionMode.NONE,
        reason_codes=["TUMOR_NOT_CONFIRMED"],
    )


def not_applicable():
    return TMEAssessment(
        state=TMEState.NOT_APPLICABLE,
        policy_version="test",
        reason_codes=["TUMOR_NOT_CONFIRMED"],
        input_measurement_version="test",
    )


def test_exact_five_class_binding_and_uncertain_is_not_a_class():
    assert [member.name for member in __import__(
        "app.domain.cells", fromlist=["BiologicalClass"]
    ).BiologicalClass] == [
        "NEOPLASTIC",
        "INFLAMMATORY",
        "CONNECTIVE",
        "DEAD",
        "EPITHELIAL",
    ]
    with pytest.raises(ValidationError):
        cell(class_id=6, class_name="UNCERTAIN")


def test_probability_vector_is_exactly_five_and_normalized():
    with pytest.raises(ValidationError):
        cell(class_probabilities=(0.5, 0.5, 0, 0))
    with pytest.raises(ValidationError):
        cell(class_probabilities=(0.5, 0.1, 0.1, 0.1, 0.1))


def test_untrusted_scale_rejects_physical_coordinates():
    with pytest.raises(ValidationError, match="physical cell coordinates"):
        AnalysisOutput(
            analysis_run_id="run",
            session_id="session",
            status=AnalysisStatus.COMPLETE,
            image_metadata=metadata(trusted=False),
            quality=quality(scale_valid=False),
            model_metadata=model_metadata(),
            cell_counts={"NEOPLASTIC": 1},
            accepted_cell_counts={"NEOPLASTIC": 1},
            uncertain_cell_counts={"NEOPLASTIC": 0},
            cells_summary=[cell(centroid_x_um=2.5, centroid_y_um=5.0)],
            tumor_assessment=unconfirmed(),
            tme_assessment=not_applicable(),
            created_at=datetime.now(timezone.utc),
        )


def test_hot_cold_excluded_require_present_tumor_context():
    with pytest.raises(ValidationError, match="requires confirmed PRESENT"):
        AnalysisOutput(
            analysis_run_id="run",
            session_id="session",
            status=AnalysisStatus.COMPLETE,
            image_metadata=metadata(trusted=True),
            quality=quality(scale_valid=True),
            model_metadata=model_metadata(),
            cell_counts={},
            accepted_cell_counts={},
            uncertain_cell_counts={},
            tumor_assessment=unconfirmed(),
            tme_assessment=TMEAssessment(
                state=TMEState.EXCLUDED,
                policy_version="test",
                input_measurement_version="test",
            ),
            created_at=datetime.now(timezone.utc),
        )


def test_absent_tumor_requires_not_applicable():
    tumor = TumorAssessment(
        status=TumorStatus.ABSENT,
        evidence_source=TumorEvidenceSource.CLINICIAN_CONFIRMED_NO_TUMOR,
        confirmed_by_user_id="clinician",
        confirmed_at=datetime.now(timezone.utc),
        tumor_region_mode=TumorRegionMode.NONE,
        reason_codes=["CLINICIAN_CONFIRMED_NO_TUMOR"],
    )
    with pytest.raises(ValidationError, match="requires NOT_APPLICABLE"):
        AnalysisOutput(
            analysis_run_id="run",
            session_id="session",
            status=AnalysisStatus.COMPLETE,
            image_metadata=metadata(trusted=True),
            quality=quality(scale_valid=True),
            model_metadata=model_metadata(),
            cell_counts={},
            accepted_cell_counts={},
            uncertain_cell_counts={},
            tumor_assessment=tumor,
            tme_assessment=TMEAssessment(
                state=TMEState.INDETERMINATE,
                policy_version="test",
                reason_codes=["INSUFFICIENT_EVIDENCE"],
                input_measurement_version="test",
            ),
            created_at=datetime.now(timezone.utc),
        )
