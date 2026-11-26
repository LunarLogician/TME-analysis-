from fastapi import APIRouter, Depends, HTTPException, Request
from app.models.schemas import AnalyticsSummary, PhenotypeDistribution
from app.db.supabase_client import get_supabase_client
from supabase import Client
from app.middleware.auth import require_admin, AuthUser
from app.middleware.rate_limit import limiter
from collections import defaultdict
from datetime import datetime

router = APIRouter()


@router.get("/summary", response_model=AnalyticsSummary)
@limiter.limit("10/minute")
async def get_analytics_summary(
    request: Request,
    user: AuthUser = Depends(require_admin),
    db: Client = Depends(get_supabase_client)
):
    """Get analytics summary"""
    try:
        # Get total sessions count
        sessions_response = db.table("biopsy_sessions").select(
            "id", count="exact"
        ).execute()
        total_sessions = len(sessions_response.data) if sessions_response.data else 0
        
        results_response = db.table("tme_assessments").select("state").execute()
        phenotype_counts = defaultdict(int)
        if results_response.data:
            for result in results_response.data:
                phenotype = str(result.get("state", "INDETERMINATE")).upper()
                phenotype_counts[phenotype] += 1
        
        phenotype_distribution = PhenotypeDistribution(
            hot_count=phenotype_counts.get("HOT", 0),
            cold_count=phenotype_counts.get("COLD", 0),
            excluded_count=phenotype_counts.get("EXCLUDED", 0)
        )
        
        try:
            clinicians_response = db.table("users").select("id").eq(
                "role", "clinician"
            ).execute()
            active_clinicians = len(clinicians_response.data or [])
        except Exception:
            # A restricted users table must not take down platform analytics.
            patients_response = db.table("patients").select("clinician_id").execute()
            active_clinicians = len({
                row.get("clinician_id") for row in (patients_response.data or [])
                if row.get("clinician_id")
            })
        
        # Get sessions per month
        sessions_response = db.table("biopsy_sessions").select("session_date").execute()
        sessions_per_month = defaultdict(int)
        if sessions_response.data:
            for session in sessions_response.data:
                if session.get("session_date"):
                    date = datetime.fromisoformat(session["session_date"].replace('Z', '+00:00'))
                    month_key = date.strftime("%Y-%m")
                    sessions_per_month[month_key] += 1
        
        return AnalyticsSummary(
            total_sessions=total_sessions,
            phenotype_distribution=phenotype_distribution,
            active_clinicians=active_clinicians,
            sessions_per_month=dict(sessions_per_month)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
