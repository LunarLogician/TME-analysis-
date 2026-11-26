"""V2 repository boundary and Supabase/PostgreSQL implementation."""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime, timezone
import logging
import time
from typing import Any, Optional, Sequence

import httpx
from supabase import Client

from app.domain.analysis import AnalysisOutput
from app.domain.cells import CellInstance
from app.domain.image_metadata import ImageMetadata
from app.domain.spatial import SpatialMeasurements
from app.domain.tme import TMEAssessment
from app.domain.tumor import TumorAssessment


logger = logging.getLogger(__name__)


class AnalysisRepository(ABC):
    @abstractmethod
    def ensure_model_version(
        self,
        *,
        metadata: dict[str, Any],
        manifest: dict[str, Any],
        calibration_version: str,
        postprocess_version: str,
    ) -> str: ...

    @abstractmethod
    def create_image_asset(
        self, *, session_id: str, metadata: ImageMetadata, storage_path: str
    ) -> None: ...

    @abstractmethod
    def create_run(self, payload: dict[str, Any]) -> None: ...

    @abstractmethod
    def get_run(self, analysis_run_id: str) -> dict[str, Any]: ...

    @abstractmethod
    def update_stage(
        self,
        analysis_run_id: str,
        stage: str,
        *,
        progress: Optional[float] = None,
        processed_tiles: Optional[int] = None,
    ) -> None: ...

    @abstractmethod
    def persist_cells(self, analysis_run_id: str, cells: Sequence[CellInstance]) -> None: ...

    @abstractmethod
    def persist_assessments(
        self,
        analysis_run_id: str,
        tumor: TumorAssessment,
        spatial: Optional[SpatialMeasurements],
        tme: TMEAssessment,
    ) -> None: ...

    @abstractmethod
    def persist_artifact(
        self, analysis_run_id: str, artifact_type: str, storage_path: str, metadata: dict
    ) -> str: ...

    @abstractmethod
    def complete_run(self, analysis_run_id: str, output: AnalysisOutput) -> None: ...

    @abstractmethod
    def fail_run(self, analysis_run_id: str, code: str, message: str) -> None: ...

    @abstractmethod
    def list_cells(
        self, analysis_run_id: str, *, offset: int, limit: int
    ) -> tuple[list[dict], int]: ...


class SupabaseAnalysisRepository(AnalysisRepository):
    def __init__(self, db: Client):
        self.db = db

    @staticmethod
    def _execute_with_transport_retry(operation):
        delays = (0.0, 0.15, 0.5)
        for attempt, delay in enumerate(delays, start=1):
            if delay:
                time.sleep(delay)
            try:
                return operation()
            except httpx.TransportError:
                if attempt == len(delays):
                    raise
                logger.warning(
                    "Transient Supabase transport failure; retrying (%s/%s)",
                    attempt,
                    len(delays),
                )

    def ensure_model_version(
        self,
        *,
        metadata: dict[str, Any],
        manifest: dict[str, Any],
        calibration_version: str,
        postprocess_version: str,
    ) -> str:
        response = self.db.table("model_versions").select("id, active").eq(
            "model_name", metadata["model_name"]
        ).eq("version", metadata["model_version"]).eq(
            "checkpoint_sha256", metadata["checkpoint_sha256"]
        ).limit(1).execute()
        self.db.table("model_versions").update({"active": False}).eq(
            "active", True
        ).execute()
        if response.data:
            model_id = str(response.data[0]["id"])
            self.db.table("model_versions").update({"active": True}).eq(
                "id", model_id
            ).execute()
            return model_id
        inserted = self.db.table("model_versions").insert(
            {
                "model_name": metadata["model_name"],
                "version": metadata["model_version"],
                "architecture": metadata["architecture"],
                "checkpoint_sha256": metadata["checkpoint_sha256"],
                "manifest_json": manifest,
                "calibration_version": calibration_version,
                "postprocess_version": postprocess_version,
                "active": True,
            }
        ).execute()
        if not inserted.data:
            raise RuntimeError("Could not register the active V2 model release")
        return str(inserted.data[0]["id"])

    def create_image_asset(
        self, *, session_id: str, metadata: ImageMetadata, storage_path: str
    ) -> None:
        self.db.table("image_assets").insert(
            {
                "id": metadata.asset_id,
                "session_id": session_id,
                "storage_path": storage_path,
                "sha256": metadata.checksum_sha256,
                "mime_type": metadata.mime_type,
                "width_px": metadata.width_px,
                "height_px": metadata.height_px,
                "mpp_x": metadata.source_mpp_x,
                "mpp_y": metadata.source_mpp_y,
                "magnification": metadata.source_magnification,
                "scale_source": metadata.scale_source,
                "scale_trusted": metadata.scale_trusted,
                "metadata_json": metadata.model_dump(mode="json"),
            }
        ).execute()

    def create_run(self, payload: dict[str, Any]) -> None:
        self.db.table("analysis_runs").insert(payload).execute()

    def get_run(self, analysis_run_id: str) -> dict[str, Any]:
        response = self._execute_with_transport_retry(
            lambda: self.db.table("analysis_runs").select(
                "*, image_assets(*), tumor_assessments(*)"
            ).eq("id", analysis_run_id).limit(1).execute()
        )
        if not response.data:
            raise KeyError(f"Analysis run {analysis_run_id} was not found")
        return response.data[0]

    def update_stage(
        self,
        analysis_run_id: str,
        stage: str,
        *,
        progress: Optional[float] = None,
        processed_tiles: Optional[int] = None,
    ) -> None:
        payload: dict[str, Any] = {"stage": stage, "status": "RUNNING"}
        if progress is not None:
            payload["progress"] = max(0.0, min(1.0, float(progress)))
        if processed_tiles is not None:
            payload["processed_tile_count"] = int(processed_tiles)
        self._execute_with_transport_retry(
            lambda: self.db.table("analysis_runs").update(payload).eq(
                "id", analysis_run_id
            ).execute()
        )

    def update_tile_count(self, analysis_run_id: str, tile_count: int) -> None:
        self._execute_with_transport_retry(
            lambda: self.db.table("analysis_runs").update(
                {"tile_count": int(tile_count)}
            ).eq("id", analysis_run_id).execute()
        )

    def persist_cells(self, analysis_run_id: str, cells: Sequence[CellInstance]) -> None:
        # Instance IDs are deterministic for an immutable run configuration.
        # Upsert avoids the delete-then-insert gap that could erase a completed
        # partial result if a worker is interrupted during a retry.
        batch_size = 500
        for start in range(0, len(cells), batch_size):
            rows = []
            for cell in cells[start : start + batch_size]:
                rows.append(
                    {
                        "analysis_run_id": analysis_run_id,
                        "instance_id": cell.instance_id,
                        "class_name": cell.class_name,
                        "class_id": int(cell.class_id),
                        "centroid_x_px": cell.centroid_x_px,
                        "centroid_y_px": cell.centroid_y_px,
                        "centroid_x_um": cell.centroid_x_um,
                        "centroid_y_um": cell.centroid_y_um,
                        "area_px": cell.area_px,
                        "area_um2": cell.area_um2,
                        "confidence": cell.class_confidence,
                        "segmentation_confidence": cell.segmentation_confidence,
                        "entropy": cell.normalized_entropy,
                        "margin": cell.top1_top2_margin,
                        "acceptance_status": cell.acceptance_status,
                        "probabilities": list(cell.class_probabilities),
                        "bbox": list(cell.bbox_xyxy),
                        "source_tile_ids": cell.source_tile_ids,
                        "tumor_membership": cell.tumor_membership,
                    }
                )
            if rows:
                self._execute_with_transport_retry(
                    lambda rows=rows: self.db.table("cell_instances").upsert(
                        rows, on_conflict="analysis_run_id,instance_id"
                    ).execute()
                )

    def persist_assessments(
        self,
        analysis_run_id: str,
        tumor: TumorAssessment,
        spatial: Optional[SpatialMeasurements],
        tme: TMEAssessment,
    ) -> None:
        self._replace_one(
            "tumor_assessments",
            analysis_run_id,
            {"analysis_run_id": analysis_run_id, **tumor.model_dump(mode="json")},
        )
        if spatial is None:
            self._execute_with_transport_retry(
                lambda: self.db.table("spatial_analysis_results").delete().eq(
                    "analysis_run_id", analysis_run_id
                ).execute()
            )
        else:
            self._execute_with_transport_retry(
                lambda: self.db.table("spatial_analysis_results").upsert(
                    {
                        "analysis_run_id": analysis_run_id,
                        "measurement_version": spatial.measurement_version,
                        "metrics": spatial.model_dump(mode="json"),
                    },
                    on_conflict="analysis_run_id",
                ).execute()
            )
        self._replace_one(
            "tme_assessments",
            analysis_run_id,
            {
                "analysis_run_id": analysis_run_id,
                "state": tme.state,
                "policy_version": tme.policy_version,
                "score": tme.score,
                "reason_codes": tme.reason_codes,
                "input_measurement_version": tme.input_measurement_version,
            },
        )

    def _replace_one(self, table: str, analysis_run_id: str, payload: dict) -> None:
        self._execute_with_transport_retry(
            lambda: self.db.table(table).upsert(
                payload, on_conflict="analysis_run_id"
            ).execute()
        )

    def persist_artifact(
        self, analysis_run_id: str, artifact_type: str, storage_path: str, metadata: dict
    ) -> str:
        response = self._execute_with_transport_retry(
            lambda: self.db.table("analysis_artifacts").upsert(
                {
                    "analysis_run_id": analysis_run_id,
                    "artifact_type": artifact_type,
                    "storage_path": storage_path,
                    "metadata": metadata,
                },
                on_conflict="analysis_run_id,artifact_type",
            ).execute()
        )
        if not response.data:
            raise RuntimeError("Analysis artifact persistence returned no record")
        return str(response.data[0]["id"])

    def complete_run(self, analysis_run_id: str, output: AnalysisOutput) -> None:
        self._execute_with_transport_retry(
            lambda: self.db.table("analysis_runs").update(
                {
                    "status": "COMPLETE",
                    "stage": "COMPLETE",
                    "progress": 1.0,
                    "accepted_cell_count": sum(output.accepted_cell_counts.values()),
                    "uncertain_cell_count": sum(output.uncertain_cell_counts.values()),
                    "completed_at": output.completed_at.isoformat()
                    if output.completed_at
                    else None,
                    "output_json": output.model_dump(mode="json"),
                }
            ).eq("id", analysis_run_id).execute()
        )
        self._update_session_for_run(analysis_run_id, "complete")

    def fail_run(self, analysis_run_id: str, code: str, message: str) -> None:
        self._execute_with_transport_retry(
            lambda: self.db.table("analysis_runs").update(
                {
                    "status": "FAILED",
                    "stage": "FAILED",
                    "failure_code": code,
                    "failure_message": message[:2000],
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                }
            ).eq("id", analysis_run_id).execute()
        )
        self._update_session_for_run(analysis_run_id, "failed")

    def _update_session_for_run(self, analysis_run_id: str, status: str) -> None:
        response = self._execute_with_transport_retry(
            lambda: self.db.table("analysis_runs").select("session_id").eq(
                "id", analysis_run_id
            ).limit(1).execute()
        )
        if response.data:
            self._execute_with_transport_retry(
                lambda: self.db.table("biopsy_sessions").update(
                    {"status": status}
                ).eq("id", response.data[0]["session_id"]).execute()
            )

    def list_cells(
        self, analysis_run_id: str, *, offset: int, limit: int
    ) -> tuple[list[dict], int]:
        start = max(0, int(offset))
        safe_limit = max(1, min(1000, int(limit)))
        response = self._execute_with_transport_retry(
            lambda: self.db.table("cell_instances").select(
                "*", count="exact"
            ).eq("analysis_run_id", analysis_run_id).order("instance_id").range(
                start, start + safe_limit - 1
            ).execute()
        )
        return list(response.data or []), int(response.count or 0)
