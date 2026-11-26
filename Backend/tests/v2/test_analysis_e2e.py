from pathlib import Path

import cv2
import numpy as np
import pytest
from skimage import data

from app.domain.tme import TMEState
from app.ml.model_manager import ModelManager
from app.repositories.analysis_repository import AnalysisRepository
from app.services.analysis_service import AnalysisService
from app.services.image_asset_service import ImageAssetService
from app.services.report_service import V2ReportService


class MemoryRepository(AnalysisRepository):
    def __init__(self):
        self.assets = {}
        self.runs = {}
        self.cells = {}
        self.assessments = {}
        self.artifacts = {}

    def ensure_model_version(
        self, *, metadata, manifest, calibration_version, postprocess_version
    ):
        return "model-version-1"

    def create_image_asset(self, *, session_id, metadata, storage_path):
        self.assets[metadata.asset_id] = {
            "id": metadata.asset_id,
            "session_id": session_id,
            "storage_path": storage_path,
            "metadata_json": metadata.model_dump(mode="json"),
        }

    def create_run(self, payload):
        self.runs[payload["id"]] = dict(payload)

    def get_run(self, analysis_run_id):
        run = dict(self.runs[analysis_run_id])
        run["image_assets"] = self.assets[run["image_asset_id"]]
        return run

    def update_stage(self, analysis_run_id, stage, *, progress=None, processed_tiles=None):
        self.runs[analysis_run_id].update({"status": "RUNNING", "stage": stage})
        if progress is not None:
            self.runs[analysis_run_id]["progress"] = progress
        if processed_tiles is not None:
            self.runs[analysis_run_id]["processed_tile_count"] = processed_tiles

    def persist_cells(self, analysis_run_id, cells):
        self.cells[analysis_run_id] = list(cells)

    def persist_assessments(self, analysis_run_id, tumor, spatial, tme):
        self.assessments[analysis_run_id] = (tumor, spatial, tme)

    def persist_artifact(self, analysis_run_id, artifact_type, storage_path, metadata):
        self.artifacts[(analysis_run_id, artifact_type)] = storage_path
        return f"artifact-{artifact_type}"

    def complete_run(self, analysis_run_id, output):
        self.runs[analysis_run_id].update(
            {
                "status": "COMPLETE",
                "stage": "COMPLETE",
                "output_json": output.model_dump(mode="json"),
            }
        )

    def fail_run(self, analysis_run_id, code, message):
        self.runs[analysis_run_id].update(
            {"status": "FAILED", "failure_code": code, "failure_message": message}
        )

    def list_cells(self, analysis_run_id, *, offset, limit):
        values = self.cells.get(analysis_run_id, [])
        rows = []
        for cell in values[offset : offset + limit]:
            payload = cell.model_dump(mode="json")
            rows.append(
                {
                    "instance_id": payload["instance_id"],
                    "class_id": payload["class_id"],
                    "class_name": payload["class_name"],
                    "centroid_x_px": payload["centroid_x_px"],
                    "centroid_y_px": payload["centroid_y_px"],
                    "centroid_x_um": payload["centroid_x_um"],
                    "centroid_y_um": payload["centroid_y_um"],
                    "area_px": payload["area_px"],
                    "area_um2": payload["area_um2"],
                    "bbox": payload["bbox_xyxy"],
                    "probabilities": payload["class_probabilities"],
                    "confidence": payload["class_confidence"],
                    "entropy": payload["normalized_entropy"],
                    "margin": payload["top1_top2_margin"],
                    "segmentation_confidence": payload["segmentation_confidence"],
                    "acceptance_status": payload["acceptance_status"],
                    "source_tile_ids": payload["source_tile_ids"],
                    "tumor_membership": payload["tumor_membership"],
                }
            )
        return rows, len(values)


def encoded_tissue_image():
    rng = np.random.default_rng(42)
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
    image = np.clip(
        image.astype(float) + rng.normal(0, 5, image.shape),
        0,
        255,
    ).astype(np.uint8)
    ok, encoded = cv2.imencode(".png", cv2.cvtColor(image, cv2.COLOR_RGB2BGR))
    assert ok
    return encoded.tobytes()


def encoded_rgb_image(image):
    ok, encoded = cv2.imencode(".png", cv2.cvtColor(image, cv2.COLOR_RGB2BGR))
    assert ok
    return encoded.tobytes()


def service(tmp_path):
    repository = MemoryRepository()
    image_assets = ImageAssetService(tmp_path)
    return (
        AnalysisService(
            manager=ModelManager(),
            repository=repository,
            image_assets=image_assets,
            batch_size=1,
        ),
        repository,
    )


def test_unknown_mpp_allows_nuclei_but_never_physical_tme(tmp_path):
    analysis, repository = service(tmp_path)
    source = encoded_tissue_image()
    run_id = analysis.prepare_analysis(
        session_id="session-1",
        patient_id="patient-1",
        source_bytes=source,
        filename="source.png",
        mime_type="image/png",
        requested_by_user_id="clinician-1",
        analysis_mode="NUCLEI_ONLY",
    )
    output = analysis.execute_analysis(run_id)
    asset = next(iter(repository.assets.values()))
    assert Path(asset["storage_path"]).read_bytes() == source
    assert output.image_metadata.scale_trusted is False
    assert output.spatial_measurements is None
    assert output.tme_assessment.state == TMEState.NOT_ASSESSABLE.value
    assert output.tme_assessment.reason_codes == ["PHYSICAL_SCALE_UNKNOWN"]
    assert all(cell.centroid_x_um is None for cell in repository.cells[run_id])


def test_confirmed_no_tumor_is_not_applicable_and_report_is_structured(tmp_path):
    analysis, repository = service(tmp_path)
    run_id = analysis.prepare_analysis(
        session_id="session-2",
        patient_id="patient-1",
        source_bytes=encoded_tissue_image(),
        filename="source.png",
        mime_type="image/png",
        requested_by_user_id="clinician-1",
        analysis_mode="NO_TUMOR",
        user_mpp_x=0.25,
        user_mpp_y=0.25,
    )
    output = analysis.execute_analysis(run_id)
    assert output.tumor_assessment.status == "ABSENT"
    assert output.tme_assessment.state == TMEState.NOT_APPLICABLE.value
    assert output.spatial_measurements is None
    report = V2ReportService(tmp_path).generate(
        output=output,
        clinical_info={"full_name": "Test Patient", "diagnosis": "Supplied history"},
    )
    assert report.read_bytes().startswith(b"%PDF")
    assert report.stat().st_size > 1000


def test_non_he_photo_is_rejected_before_asset_or_run_is_created(tmp_path):
    analysis, repository = service(tmp_path)

    with pytest.raises(ValueError, match="UNSUPPORTED_NON_HE_IMAGE"):
        analysis.prepare_analysis(
            session_id="session-rejected",
            patient_id="patient-1",
            source_bytes=encoded_rgb_image(data.chelsea()),
            filename="pet.png",
            mime_type="image/png",
            requested_by_user_id="clinician-1",
        )

    assert repository.assets == {}
    assert repository.runs == {}
    assert not (tmp_path / "analysis-source").exists()
