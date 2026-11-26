"""Authenticated, paginated TME-Insight analysis API."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Optional
from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from supabase import Client

from app.db.supabase_client import get_supabase_client
from app.domain.analysis import AnalysisOutput
from app.domain.tumor import TumorRegionMode
from app.middleware.auth import AuthUser, require_auth, require_clinician
from app.repositories.analysis_repository import SupabaseAnalysisRepository
from app.services.analysis_service import AnalysisService
from app.services.report_service import V2ReportService
from app.utils.access_control import verify_patient_access


router = APIRouter(prefix="/v2")
ANALYSIS_MODES = {"NUCLEI_ONLY", "PATHOLOGIST_CONFIRMED_TME", "NO_TUMOR"}


class TumorContextRequest(BaseModel):
    status: str = Field(pattern="^(PRESENT|ABSENT|INDETERMINATE)$")
    region_mode: TumorRegionMode = TumorRegionMode.WHOLE_ROI
    region_artifact_id: Optional[str] = None
    tumor_polygon_px: Optional[list[tuple[float, float]]] = Field(
        default=None, min_length=3
    )


def _analysis_service(request: Request, db: Client) -> AnalysisService:
    service = getattr(request.app.state, "analysis_service", None)
    if service is None:
        raise HTTPException(status_code=503, detail="V2 analysis service is unavailable")
    return service.with_repository(SupabaseAnalysisRepository(db))


def _authorize_session(
    session_id: str, user: AuthUser, db: Client
) -> dict:
    response = db.table("biopsy_sessions").select("id, patient_id, status").eq(
        "id", session_id
    ).limit(1).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Session not found")
    session = response.data[0]
    if not verify_patient_access(session["patient_id"], user, db):
        raise HTTPException(status_code=403, detail="Access denied")
    return session


def _authorize_run(
    analysis_run_id: str, user: AuthUser, db: Client
) -> tuple[dict, dict]:
    response = db.table("analysis_runs").select("*").eq(
        "id", analysis_run_id
    ).limit(1).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Analysis run not found")
    run = response.data[0]
    session = _authorize_session(run["session_id"], user, db)
    return run, session


def _run_response(run: dict):
    if run.get("output_json"):
        return run["output_json"]
    return {
        "analysis_run_id": run["id"],
        "session_id": run["session_id"],
        "status": run["status"],
        "stage": run["stage"],
        "progress": run.get("progress", 0),
        "tile_count": run.get("tile_count", 0),
        "processed_tile_count": run.get("processed_tile_count", 0),
        "failure_code": run.get("failure_code"),
        "failure_message": run.get("failure_message"),
    }


@router.post("/sessions/{session_id}/analysis", status_code=202)
async def start_analysis(
    session_id: UUID,
    request: Request,
    file: UploadFile = File(...),
    analysis_mode: str = Form("NUCLEI_ONLY"),
    mpp_x: Optional[float] = Form(None),
    mpp_y: Optional[float] = Form(None),
    magnification: Optional[float] = Form(None),
    tumor_region_mode: str = Form("WHOLE_ROI"),
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client),
):
    session = _authorize_session(str(session_id), user, db)
    mode = analysis_mode.upper()
    if mode not in ANALYSIS_MODES:
        raise HTTPException(status_code=422, detail="Unsupported analysis_mode")
    try:
        region_mode = TumorRegionMode(tumor_region_mode.upper())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Unsupported tumor_region_mode") from exc
    maximum_bytes = int(os.getenv("TME_MAX_UPLOAD_BYTES", str(100 * 1024 * 1024)))
    source_bytes = await file.read(maximum_bytes + 1)
    if not source_bytes:
        raise HTTPException(status_code=422, detail="Uploaded source image is empty")
    if len(source_bytes) > maximum_bytes:
        raise HTTPException(status_code=413, detail="Uploaded source image is too large")
    service = _analysis_service(request, db)
    try:
        analysis_run_id = service.prepare_analysis(
            session_id=str(session_id),
            patient_id=session["patient_id"],
            source_bytes=source_bytes,
            filename=file.filename or "source.img",
            mime_type=file.content_type,
            requested_by_user_id=user.user_id,
            analysis_mode=mode,
            user_mpp_x=mpp_x,
            user_mpp_y=mpp_y,
            user_magnification=magnification,
            tumor_region_mode=region_mode.value,
        )
        try:
            request.app.state.analysis_queue.enqueue(analysis_run_id)
        except Exception as exc:
            service.repository.fail_run(
                analysis_run_id, "QUEUE_UNAVAILABLE", str(exc)
            )
            raise HTTPException(
                status_code=503,
                detail="The analysis queue is unavailable; the run was marked failed",
            ) from exc
        db.table("biopsy_sessions").update({"status": "processing"}).eq(
            "id", str(session_id)
        ).execute()
    except FileExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This session already has an immutable source image",
        ) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {
        "analysis_run_id": analysis_run_id,
        "session_id": str(session_id),
        "status": "QUEUED",
        "stage": "QUEUED",
    }


@router.post("/analysis/{analysis_run_id}/retry", status_code=202)
def retry_analysis(
    analysis_run_id: UUID,
    request: Request,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client),
):
    run, session = _authorize_run(str(analysis_run_id), user, db)
    if run.get("status") != "FAILED":
        raise HTTPException(
            status_code=409,
            detail="Only a failed analysis run can be retried",
        )
    db.table("analysis_runs").update(
        {
            "status": "QUEUED",
            "stage": "QUEUED",
            "progress": 0.0,
            "processed_tile_count": 0,
            "failure_code": None,
            "failure_message": None,
            "completed_at": None,
        }
    ).eq("id", str(analysis_run_id)).execute()
    service = _analysis_service(request, db)
    try:
        request.app.state.analysis_queue.enqueue(str(analysis_run_id))
    except Exception as exc:
        service.repository.fail_run(
            str(analysis_run_id), "QUEUE_UNAVAILABLE", str(exc)
        )
        raise HTTPException(
            status_code=503,
            detail="The analysis queue is unavailable; the run remains failed",
        ) from exc
    db.table("biopsy_sessions").update({"status": "processing"}).eq(
        "id", session["id"]
    ).execute()
    return {
        "analysis_run_id": str(analysis_run_id),
        "session_id": session["id"],
        "status": "QUEUED",
        "stage": "QUEUED",
    }


@router.get("/analysis/{analysis_run_id}")
def get_analysis(
    analysis_run_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    run, _ = _authorize_run(str(analysis_run_id), user, db)
    return _run_response(run)


@router.get("/sessions/{session_id}/analysis")
def get_latest_session_analysis(
    session_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    _authorize_session(str(session_id), user, db)
    response = (
        db.table("analysis_runs")
        .select("*")
        .eq("session_id", str(session_id))
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    if not response.data:
        raise HTTPException(
            status_code=404,
            detail="No analysis found for this session",
        )
    return _run_response(response.data[0])


@router.get("/analysis/{analysis_run_id}/cells")
def get_cells(
    analysis_run_id: UUID,
    offset: int = Query(0, ge=0),
    limit: int = Query(200, ge=1, le=1000),
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    _authorize_run(str(analysis_run_id), user, db)
    rows, total = SupabaseAnalysisRepository(db).list_cells(
        str(analysis_run_id), offset=offset, limit=limit
    )
    return {"items": rows, "offset": offset, "limit": limit, "total": total}


def _completed_section(run: dict, section: str):
    output = run.get("output_json")
    if not output:
        raise HTTPException(status_code=409, detail="Analysis is not complete")
    return output.get(section)


@router.get("/analysis/{analysis_run_id}/quality")
def get_quality(
    analysis_run_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    run, _ = _authorize_run(str(analysis_run_id), user, db)
    return _completed_section(run, "quality")


@router.get("/analysis/{analysis_run_id}/tumor")
def get_tumor(
    analysis_run_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    run, _ = _authorize_run(str(analysis_run_id), user, db)
    return _completed_section(run, "tumor_assessment")


@router.get("/analysis/{analysis_run_id}/spatial")
def get_spatial(
    analysis_run_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    run, _ = _authorize_run(str(analysis_run_id), user, db)
    return {
        "spatial_measurements": _completed_section(run, "spatial_measurements"),
        "tme_assessment": _completed_section(run, "tme_assessment"),
    }


@router.get("/analysis/{analysis_run_id}/artifacts")
def get_artifacts(
    analysis_run_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    _authorize_run(str(analysis_run_id), user, db)
    response = db.table("analysis_artifacts").select(
        "id, artifact_type, metadata, created_at"
    ).eq("analysis_run_id", str(analysis_run_id)).execute()
    return {"items": response.data or []}


@router.get("/analysis/{analysis_run_id}/overlay")
def get_overlay(
    analysis_run_id: UUID,
    request: Request,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    _authorize_run(str(analysis_run_id), user, db)
    response = db.table("analysis_artifacts").select("storage_path, metadata").eq(
        "analysis_run_id", str(analysis_run_id)
    ).eq("artifact_type", "overlay").limit(1).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Overlay not found")
    row = response.data[0]
    path = Path(row["storage_path"]).resolve()
    root = _analysis_service(request, db).image_assets.storage_root.resolve()
    if root not in path.parents or not path.is_file():
        raise HTTPException(status_code=404, detail="Overlay is unavailable")
    return FileResponse(path, media_type="image/png", filename=f"{analysis_run_id}-overlay.png")


@router.post("/analysis/{analysis_run_id}/report", status_code=201)
def generate_v2_report(
    analysis_run_id: UUID,
    request: Request,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client),
):
    run, session = _authorize_run(str(analysis_run_id), user, db)
    output = run.get("output_json")
    if not output:
        raise HTTPException(status_code=409, detail="Analysis is not complete")
    patient_response = db.table("patients").select(
        "full_name, diagnosis, gender, date_of_birth"
    ).eq("id", session["patient_id"]).limit(1).execute()
    clinical_info = patient_response.data[0] if patient_response.data else {}
    service = _analysis_service(request, db)
    report_path = V2ReportService(service.image_assets.storage_root).generate(
        output=AnalysisOutput.model_validate(output),
        clinical_info=clinical_info,
    )
    service.repository.persist_artifact(
        str(analysis_run_id),
        "report",
        str(report_path),
        {"media_type": "application/pdf"},
    )
    return {
        "analysis_run_id": str(analysis_run_id),
        "status": "COMPLETE",
        "report_url": str(request.url_for("download_v2_report", analysis_run_id=str(analysis_run_id))),
    }


@router.get("/analysis/{analysis_run_id}/report", name="download_v2_report")
def download_v2_report(
    analysis_run_id: UUID,
    request: Request,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client),
):
    _authorize_run(str(analysis_run_id), user, db)
    response = db.table("analysis_artifacts").select("storage_path").eq(
        "analysis_run_id", str(analysis_run_id)
    ).eq("artifact_type", "report").limit(1).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="V2 report not found")
    path = Path(response.data[0]["storage_path"]).resolve()
    root = _analysis_service(request, db).image_assets.storage_root.resolve()
    if root not in path.parents or not path.is_file():
        raise HTTPException(status_code=404, detail="V2 report is unavailable")
    return FileResponse(
        path,
        media_type="application/pdf",
        filename=f"tme-insight-{analysis_run_id}.pdf",
    )


@router.post("/analysis/{analysis_run_id}/tumor-context")
def update_tumor_context(
    analysis_run_id: UUID,
    payload: TumorContextRequest,
    request: Request,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client),
):
    _authorize_run(str(analysis_run_id), user, db)
    present = True if payload.status == "PRESENT" else False if payload.status == "ABSENT" else None
    region_mode = payload.region_mode
    region_artifact_id = payload.region_artifact_id
    service = _analysis_service(request, db)
    if payload.tumor_polygon_px is not None:
        if present is not True:
            raise HTTPException(
                status_code=422,
                detail="A tumor-region polygon requires PRESENT tumor context",
            )
        region_path = service.artifacts.store_tumor_region(
            analysis_run_id=str(analysis_run_id),
            polygon_px=payload.tumor_polygon_px,
        )
        region_artifact_id = service.repository.persist_artifact(
            str(analysis_run_id),
            "tumor_region",
            str(region_path),
            {"media_type": "application/geo+json"},
        )
        region_mode = TumorRegionMode.ANNOTATED_REGION
    output = service.update_tumor_context(
        str(analysis_run_id),
        present=present,
        user_id=user.user_id,
        region_mode=region_mode,
        region_artifact_id=region_artifact_id,
        tumor_polygon_px=payload.tumor_polygon_px,
    )
    return output.model_dump(mode="json")


@router.post("/analysis/{analysis_run_id}/recompute-tme")
def recompute_tme(
    analysis_run_id: UUID,
    request: Request,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client),
):
    run, _ = _authorize_run(str(analysis_run_id), user, db)
    tumor = _completed_section(run, "tumor_assessment")
    status_value = tumor["status"]
    present = True if status_value == "PRESENT" else False if status_value == "ABSENT" else None
    output = _analysis_service(request, db).update_tumor_context(
        str(analysis_run_id),
        present=present,
        user_id=user.user_id,
        region_mode=TumorRegionMode(tumor.get("tumor_region_mode") or "NONE"),
        region_artifact_id=tumor.get("tumor_region_artifact_id"),
    )
    return output.model_dump(mode="json")
