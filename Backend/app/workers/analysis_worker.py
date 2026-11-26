"""RQ job entry point; payload contains only the analysis-run ID."""

from __future__ import annotations

from app.db.supabase_client import create_supabase_service_client
from app.ml.model_manager import ModelManager
from app.repositories.analysis_repository import SupabaseAnalysisRepository
from app.services.analysis_service import AnalysisService


_worker_service: AnalysisService | None = None


def get_worker_service() -> AnalysisService:
    global _worker_service
    if _worker_service is None:
        manager = ModelManager()
        repository = SupabaseAnalysisRepository(create_supabase_service_client())
        _worker_service = AnalysisService(manager=manager, repository=repository)
    return _worker_service


def execute_analysis_job(analysis_run_id: str) -> dict:
    """Idempotent worker entrypoint referenced by its import path from RQ."""
    service = get_worker_service()
    run = service.repository.get_run(analysis_run_id)
    if run.get("status") == "COMPLETE" and run.get("output_json"):
        return run["output_json"]
    output = service.execute_analysis(analysis_run_id)
    return output.model_dump(mode="json")
