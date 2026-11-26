"""Canonical TME-Insight V2 analysis orchestration."""

from __future__ import annotations

import os
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional, Sequence
from uuid import uuid4

from app.domain.analysis import AnalysisOutput, AnalysisStatus, ModelMetadata
from app.domain.cells import AcceptanceStatus, BIOLOGICAL_CLASS_ORDER, CellInstance
from app.domain.image_metadata import ImageMetadata
from app.domain.quality import QualityStatus
from app.domain.tme import TMEAssessment, TMEState
from app.domain.tumor import TumorRegionMode
from app.ml.calibration import ConfidenceCalibrator
from app.ml.model_manager import ModelManager
from app.ml.postprocessing import InstancePostprocessor
from app.ml.predictor import NucleiPredictor
from app.ml.preprocessing import ScaleResolver, normalize_rgb_batch, resample_to_model_scale
from app.ml.stitching import InstanceStitcher
from app.ml.tiling import TileGenerator
from app.repositories.analysis_repository import AnalysisRepository

from .artifact_service import ArtifactService
from .image_asset_service import ImageAssetService
from .quality_service import QualityController, compute_tissue_mask
from .spatial_engine import SpatialEngine
from .tme_policy import TMEPolicyV1
from .tumor_context_service import TumorContextService


class AnalysisService:
    STAGES = (
        "QUEUED",
        "VALIDATING_IMAGE",
        "READING_METADATA",
        "RESAMPLING",
        "TISSUE_MASKING",
        "TILING",
        "NUCLEAR_INFERENCE",
        "INSTANCE_RECONSTRUCTION",
        "CALIBRATION",
        "STITCHING",
        "PERSISTING_CELLS",
        "AWAITING_TUMOR_CONTEXT",
        "SPATIAL_ANALYSIS",
        "TME_INTERPRETATION",
        "RENDERING_ARTIFACTS",
        "COMPLETE",
        "FAILED",
    )

    def __init__(
        self,
        *,
        manager: ModelManager,
        repository: AnalysisRepository,
        image_assets: Optional[ImageAssetService] = None,
        scale_resolver: Optional[ScaleResolver] = None,
        tile_overlap: Optional[int] = None,
        batch_size: Optional[int] = None,
    ):
        self.manager = manager
        self.repository = repository
        self.image_assets = image_assets or ImageAssetService()
        self.scale_resolver = scale_resolver or ScaleResolver()
        self.quality_controller = QualityController()
        self.predictor = NucleiPredictor(manager)
        self.postprocessor = InstancePostprocessor(manager.postprocess_config)
        self.calibrator = ConfidenceCalibrator(manager.calibration_config)
        self.stitcher = InstanceStitcher(self.calibrator)
        self.spatial_engine = SpatialEngine()
        self.tme_policy = TMEPolicyV1()
        self.tumor_context = TumorContextService()
        self.tile_overlap = int(tile_overlap or os.getenv("TME_V2_TILE_OVERLAP", "64"))
        self.batch_size = int(batch_size or os.getenv("TME_V2_BATCH_SIZE", "4"))
        self.artifacts = ArtifactService(self.image_assets.storage_root)

    def with_repository(self, repository: AnalysisRepository) -> "AnalysisService":
        """Clone the configured pipeline around a request/job-local repository."""
        return AnalysisService(
            manager=self.manager,
            repository=repository,
            image_assets=self.image_assets,
            scale_resolver=self.scale_resolver,
            tile_overlap=self.tile_overlap,
            batch_size=self.batch_size,
        )

    def prepare_analysis(
        self,
        *,
        session_id: str,
        patient_id: str,
        source_bytes: bytes,
        filename: str,
        mime_type: Optional[str],
        requested_by_user_id: str,
        analysis_mode: str = "NUCLEI_ONLY",
        user_mpp_x: Optional[float] = None,
        user_mpp_y: Optional[float] = None,
        user_magnification: Optional[float] = None,
        tumor_region_mode: str = "WHOLE_ROI",
    ) -> str:
        scanner_metadata = self.image_assets.extract_scanner_metadata(source_bytes)
        scale = self.scale_resolver.resolve(
            scanner_metadata,
            user_mpp_x=user_mpp_x,
            user_mpp_y=user_mpp_y,
            user_magnification=user_magnification,
        )
        # Reject unsupported uploads before persisting an asset, creating an
        # analysis run, or scheduling expensive nuclei inference. The same
        # check is repeated during execution as a defense against old/retried
        # assets bypassing this upload path.
        upload_image = self.image_assets.decode(source_bytes)
        if not self.quality_controller.assess_he_compatibility(upload_image).valid:
            raise ValueError("UNSUPPORTED_NON_HE_IMAGE")
        asset_id = str(uuid4())
        persisted = self.image_assets.persist(
            source_bytes=source_bytes,
            filename=filename,
            mime_type=mime_type,
            patient_id=patient_id,
            session_id=session_id,
            scale=scale,
            asset_id=asset_id,
        )
        self.repository.create_image_asset(
            session_id=session_id,
            metadata=persisted.metadata,
            storage_path=str(persisted.source_path),
        )
        analysis_run_id = str(uuid4())
        calibration_version = self._config_version(
            "calibration", self.manager.calibration_config
        )
        postprocess_version = self._config_version(
            "postprocess", self.manager.postprocess_config
        )
        model_version_id = self.repository.ensure_model_version(
            metadata=self.manager.model_metadata,
            manifest=self.manager.manifest,
            calibration_version=calibration_version,
            postprocess_version=postprocess_version,
        )
        config_snapshot = {
            "analysis_mode": analysis_mode,
            "requested_by_user_id": requested_by_user_id,
            "tumor_region_mode": tumor_region_mode,
            "tile_overlap": self.tile_overlap,
            "batch_size": self.batch_size,
            "model_manifest": self.manager.manifest,
            "postprocess": self.manager.postprocess_config,
            "calibration": self.manager.calibration_config,
        }
        self.repository.create_run(
            {
                "id": analysis_run_id,
                "session_id": session_id,
                "image_asset_id": asset_id,
                "model_version_id": model_version_id,
                "status": "QUEUED",
                "stage": "QUEUED",
                "progress": 0.0,
                "effective_mpp_x": self.manager.expected_mpp if scale.trusted else None,
                "effective_mpp_y": self.manager.expected_mpp if scale.trusted else None,
                "tile_count": 0,
                "processed_tile_count": 0,
                "accepted_cell_count": 0,
                "uncertain_cell_count": 0,
                "config_snapshot": config_snapshot,
            }
        )
        return analysis_run_id

    def execute_analysis(self, analysis_run_id: str) -> AnalysisOutput:
        created_at = datetime.now(timezone.utc)
        try:
            run = self.repository.get_run(analysis_run_id)
            asset_row = run["image_assets"]
            if isinstance(asset_row, list):
                asset_row = asset_row[0]
            metadata = ImageMetadata.model_validate(asset_row["metadata_json"])
            asset = self.image_assets.load(metadata, asset_row["storage_path"])
            self._stage(analysis_run_id, "VALIDATING_IMAGE", 0.03)
            quality = self.quality_controller.assess(
                asset.image_rgb, scale_valid=metadata.scale_trusted
            )
            if quality.status == QualityStatus.FAIL.value and not self._development_qc_override():
                tumor = self.tumor_context.unconfirmed()
                tme = TMEAssessment(
                    state=TMEState.NOT_ASSESSABLE,
                    policy_version=self.tme_policy.policy_version,
                    reason_codes=["IMAGE_QUALITY_FAILED", *quality.failures],
                    input_measurement_version=self.spatial_engine.measurement_version,
                )
                output = self._build_output(
                    analysis_run_id=analysis_run_id,
                    run=run,
                    metadata=metadata,
                    quality=quality,
                    cells=[],
                    tumor=tumor,
                    spatial=None,
                    tme=tme,
                    artifacts={},
                    warnings=quality.warnings,
                    created_at=created_at,
                )
                self.repository.persist_assessments(analysis_run_id, tumor, None, tme)
                self.repository.complete_run(analysis_run_id, output)
                return output

            self._stage(analysis_run_id, "RESAMPLING", 0.06)
            scale = self.scale_resolver.resolve(
                {
                    "openslide.mpp-x": metadata.source_mpp_x,
                    "openslide.mpp-y": metadata.source_mpp_y,
                    "openslide.objective-power": metadata.source_magnification,
                }
                if metadata.scale_trusted
                else {}
            )
            model_image, source_transform = resample_to_model_scale(
                asset.image_rgb, scale, self.manager.expected_mpp
            )
            self._stage(analysis_run_id, "TISSUE_MASKING", 0.09)
            tissue_mask_model = compute_tissue_mask(model_image)
            self._stage(analysis_run_id, "TILING", 0.12)
            tiler = TileGenerator(
                self.manager.patch_size,
                overlap=self.tile_overlap,
                minimum_tissue_fraction=float(os.getenv("TME_V2_MIN_TILE_TISSUE", "0.05")),
            )
            tiles = tiler.generate(model_image, tissue_mask_model)
            if not tiles:
                raise ValueError("NO_TISSUE_TILES")
            self._update_tile_count(analysis_run_id, len(tiles))
            local_instances = []
            inference_diagnostics: list[dict[str, Any]] = []
            for start in range(0, len(tiles), self.batch_size):
                batch_tiles = tiles[start : start + self.batch_size]
                batch = normalize_rgb_batch(
                    [tile.image for tile in batch_tiles], self.manager.normalization
                )
                dense = self.predictor.predict_batch(batch)
                inference_diagnostics.append(
                    {
                        "inference_ms": dense.inference_ms,
                        "batch_size": dense.batch_size,
                        "device": dense.device,
                        "peak_vram": dense.peak_vram,
                    }
                )
                reconstructed = self.postprocessor.reconstruct(dense, batch_tiles)
                classified = self.postprocessor.classify_and_fuse(
                    reconstructed,
                    self.manager.instance_classifier,
                    device=self.manager.device,
                )
                local_instances.extend(self.calibrator.apply(classified))
                processed = min(start + len(batch_tiles), len(tiles))
                self.repository.update_stage(
                    analysis_run_id,
                    "NUCLEAR_INFERENCE",
                    progress=0.12 + 0.55 * processed / len(tiles),
                    processed_tiles=processed,
                )
            self._stage(analysis_run_id, "STITCHING", 0.70)
            cells = self.stitcher.stitch(
                local_instances, source_transform=source_transform
            )
            self._stage(analysis_run_id, "PERSISTING_CELLS", 0.77)
            self.repository.persist_cells(analysis_run_id, cells)
            config = run.get("config_snapshot") or {}
            tumor = self._resolve_initial_tumor(config, cells)
            spatial = None
            self._stage(analysis_run_id, "TME_INTERPRETATION", 0.84)
            if metadata.scale_trusted and tumor.status == "PRESENT":
                self._stage(analysis_run_id, "SPATIAL_ANALYSIS", 0.81)
                source_tissue_mask = compute_tissue_mask(asset.image_rgb)
                spatial = self.spatial_engine.measure(
                    cells=cells,
                    tumor=tumor,
                    metadata=metadata,
                    tissue_area_px=int(source_tissue_mask.sum()),
                )
            tme = self.tme_policy.evaluate(
                spatial=spatial, tumor=tumor, quality=quality, metadata=metadata
            )
            self.repository.persist_assessments(analysis_run_id, tumor, spatial, tme)
            self._stage(analysis_run_id, "RENDERING_ARTIFACTS", 0.90)
            source_tissue_mask = compute_tissue_mask(asset.image_rgb)
            artifacts = self.artifacts.render_and_store(
                analysis_run_id=analysis_run_id,
                source_rgb=asset.image_rgb,
                cells=cells,
                tissue_mask=source_tissue_mask,
                diagnostics={
                    "model": self.manager.model_metadata,
                    "tile_count": len(tiles),
                    "local_instance_count": len(local_instances),
                    "stitched_cell_count": len(cells),
                    "inference_batches": inference_diagnostics,
                },
            )
            for artifact_type, artifact in artifacts.items():
                self.repository.persist_artifact(
                    analysis_run_id,
                    artifact_type,
                    artifact["path"],
                    {"media_type": artifact["media_type"]},
                )
            output = self._build_output(
                analysis_run_id=analysis_run_id,
                run=run,
                metadata=metadata,
                quality=quality,
                cells=cells,
                tumor=tumor,
                spatial=spatial,
                tme=tme,
                artifacts=artifacts,
                warnings=quality.warnings,
                created_at=created_at,
            )
            self.repository.complete_run(analysis_run_id, output)
            return output
        except Exception as exc:
            self.repository.fail_run(
                analysis_run_id, type(exc).__name__.upper(), str(exc)
            )
            raise

    def update_tumor_context(
        self,
        analysis_run_id: str,
        *,
        present: Optional[bool],
        user_id: str,
        region_mode: TumorRegionMode = TumorRegionMode.WHOLE_ROI,
        region_artifact_id: Optional[str] = None,
        tumor_polygon_px: Optional[Sequence[tuple[float, float]]] = None,
    ) -> AnalysisOutput:
        """Recompute spatial/TME state from persisted cells without neural inference."""
        run = self.repository.get_run(analysis_run_id)
        if run.get("status") != "COMPLETE" or not run.get("output_json"):
            raise ValueError("ANALYSIS_NOT_COMPLETE")
        previous = AnalysisOutput.model_validate(run["output_json"])
        cells: list[CellInstance] = []
        offset = 0
        while True:
            rows, total = self.repository.list_cells(
                analysis_run_id, offset=offset, limit=1000
            )
            cells.extend(self._cell_from_row(row) for row in rows)
            offset += len(rows)
            if not rows or offset >= total:
                break
        accepted_neo = sum(
            cell.class_name == "NEOPLASTIC"
            and cell.acceptance_status == AcceptanceStatus.ACCEPTED.value
            for cell in cells
        )
        uncertain_neo = sum(
            cell.class_name == "NEOPLASTIC"
            and cell.acceptance_status == AcceptanceStatus.UNCERTAIN.value
            for cell in cells
        )
        if present is None:
            tumor = self.tumor_context.unconfirmed(
                confident_neoplastic_count=accepted_neo,
                uncertain_neoplastic_count=uncertain_neo,
            )
        else:
            tumor = self.tumor_context.clinician_confirmed(
                present=present,
                user_id=user_id,
                region_mode=region_mode,
                region_artifact_id=region_artifact_id,
                confident_neoplastic_count=accepted_neo,
                uncertain_neoplastic_count=uncertain_neo,
            )
        spatial = None
        if previous.image_metadata.scale_trusted and tumor.status == "PRESENT":
            tissue_area_px = int(
                previous.quality.tissue_fraction
                * previous.image_metadata.width_px
                * previous.image_metadata.height_px
            )
            spatial = self.spatial_engine.measure(
                cells=cells,
                tumor=tumor,
                metadata=previous.image_metadata,
                tissue_area_px=tissue_area_px,
                tumor_polygon_px=tumor_polygon_px,
            )
        tme = self.tme_policy.evaluate(
            spatial=spatial,
            tumor=tumor,
            quality=previous.quality,
            metadata=previous.image_metadata,
        )
        self.repository.persist_assessments(analysis_run_id, tumor, spatial, tme)
        updated = previous.model_copy(
            update={
                "tumor_assessment": tumor,
                "spatial_measurements": spatial,
                "tme_assessment": tme,
                "completed_at": datetime.now(timezone.utc),
            }
        )
        # Revalidate cross-object invariants after model_copy's trusted update.
        updated = AnalysisOutput.model_validate(updated.model_dump(mode="json"))
        self.repository.complete_run(analysis_run_id, updated)
        return updated

    @staticmethod
    def _cell_from_row(row: dict[str, Any]) -> CellInstance:
        return CellInstance(
            instance_id=row["instance_id"],
            class_id=row["class_id"],
            class_name=row["class_name"],
            centroid_x_px=row["centroid_x_px"],
            centroid_y_px=row["centroid_y_px"],
            centroid_x_um=row.get("centroid_x_um"),
            centroid_y_um=row.get("centroid_y_um"),
            area_px=row["area_px"],
            area_um2=row.get("area_um2"),
            bbox_xyxy=tuple(row["bbox"]),
            class_probabilities=tuple(row["probabilities"]),
            class_confidence=row["confidence"],
            normalized_entropy=row["entropy"],
            top1_top2_margin=row["margin"],
            segmentation_confidence=row.get("segmentation_confidence"),
            acceptance_status=row["acceptance_status"],
            source_tile_ids=list(row["source_tile_ids"]),
            tumor_membership=row.get("tumor_membership"),
        )

    def _resolve_initial_tumor(
        self, config: dict[str, Any], cells: Sequence[CellInstance]
    ):
        accepted_neo = sum(
            cell.class_name == "NEOPLASTIC"
            and cell.acceptance_status == AcceptanceStatus.ACCEPTED.value
            for cell in cells
        )
        uncertain_neo = sum(
            cell.class_name == "NEOPLASTIC"
            and cell.acceptance_status == AcceptanceStatus.UNCERTAIN.value
            for cell in cells
        )
        mode = str(config.get("analysis_mode", "NUCLEI_ONLY")).upper()
        if mode == "PATHOLOGIST_CONFIRMED_TME":
            return self.tumor_context.clinician_confirmed(
                present=True,
                user_id=config["requested_by_user_id"],
                region_mode=TumorRegionMode(config.get("tumor_region_mode", "WHOLE_ROI")),
                confident_neoplastic_count=accepted_neo,
                uncertain_neoplastic_count=uncertain_neo,
            )
        if mode == "NO_TUMOR":
            return self.tumor_context.clinician_confirmed(
                present=False,
                user_id=config["requested_by_user_id"],
                confident_neoplastic_count=accepted_neo,
                uncertain_neoplastic_count=uncertain_neo,
            )
        return self.tumor_context.unconfirmed(
            confident_neoplastic_count=accepted_neo,
            uncertain_neoplastic_count=uncertain_neo,
        )

    def _build_output(
        self,
        *,
        analysis_run_id: str,
        run: dict,
        metadata: ImageMetadata,
        quality,
        cells: Sequence[CellInstance],
        tumor,
        spatial,
        tme,
        artifacts,
        warnings,
        created_at,
    ) -> AnalysisOutput:
        counts = {
            name: sum(cell.class_name == name for cell in cells)
            for name in BIOLOGICAL_CLASS_ORDER
        }
        accepted = {
            name: sum(
                cell.class_name == name
                and cell.acceptance_status == AcceptanceStatus.ACCEPTED.value
                for cell in cells
            )
            for name in BIOLOGICAL_CLASS_ORDER
        }
        uncertain = {
            name: sum(
                cell.class_name == name
                and cell.acceptance_status == AcceptanceStatus.UNCERTAIN.value
                for cell in cells
            )
            for name in BIOLOGICAL_CLASS_ORDER
        }
        completed = datetime.now(timezone.utc)
        return AnalysisOutput(
            analysis_run_id=analysis_run_id,
            session_id=run["session_id"],
            status=AnalysisStatus.COMPLETE,
            stage="COMPLETE",
            progress=1.0,
            image_metadata=metadata,
            quality=quality,
            model_metadata=ModelMetadata(**self.manager.model_metadata),
            cell_counts=counts,
            accepted_cell_counts=accepted,
            uncertain_cell_counts=uncertain,
            # Full cells remain paginated in cell_instances/GeoJSON.
            cells_summary=list(cells[:100]),
            tumor_assessment=tumor,
            spatial_measurements=spatial,
            tme_assessment=tme,
            warnings=list(warnings),
            artifacts=artifacts,
            created_at=created_at,
            completed_at=completed,
        )

    def _stage(self, analysis_run_id: str, stage: str, progress: float) -> None:
        self.repository.update_stage(analysis_run_id, stage, progress=progress)

    def _update_tile_count(self, analysis_run_id: str, tile_count: int) -> None:
        updater = getattr(self.repository, "update_tile_count", None)
        if updater is not None:
            updater(analysis_run_id, tile_count)

    @staticmethod
    def _development_qc_override() -> bool:
        return (
            os.getenv("ENV", "development").lower() != "production"
            and os.getenv("TME_V2_ALLOW_QC_FAIL", "false").lower()
            in {"1", "true", "yes", "on"}
        )

    @staticmethod
    def _config_version(prefix: str, config: dict[str, Any]) -> str:
        payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
        return f"{prefix}-{hashlib.sha256(payload).hexdigest()[:16]}"
