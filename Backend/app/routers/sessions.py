from fastapi import APIRouter, Depends, HTTPException, status, Request
from uuid import UUID
from app.models.schemas import SessionCreate, SessionResponse
from app.db.supabase_client import get_supabase_client
from supabase import Client
from app.middleware.auth import require_auth, require_clinician, AuthUser
from app.middleware.rate_limit import limiter
from app.utils.access_control import verify_patient_access

router = APIRouter()


@router.post("/", response_model=SessionResponse, status_code=201)
@limiter.limit("30/minute")
async def create_session(
    request: Request,
    session: SessionCreate,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client)
):
    """
    Create new biopsy session.

    The full session payload (patient_id + optional image_url) is sent as a
    JSON body. image_url is optional at creation time; it can be populated
    later when the image is uploaded.
    """
    try:
        # Verify patient ownership (clinicians can only create sessions for their own patients)
        patient_response = db.table("patients").select("id").eq(
            "id", str(session.patient_id)
        ).eq("clinician_id", user.user_id).execute()

        if not patient_response.data:
            raise HTTPException(status_code=403, detail="Patient access denied")

        insert_data = {
            "patient_id": str(session.patient_id),
            "status": "pending"
        }
        if session.image_url:
            insert_data["image_url"] = session.image_url

        response = db.table("biopsy_sessions").insert(insert_data).execute()

        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=400, detail="Failed to create session")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{session_id}", response_model=SessionResponse)
@limiter.limit("30/minute")
async def get_session(
    request: Request,
    session_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client)
):
    """Get session details and current status"""
    try:
        response = db.table("biopsy_sessions").select("*").eq(
            "id", str(session_id)
        ).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="Session not found")
        
        session_data = response.data[0]
        
        if not verify_patient_access(session_data["patient_id"], user, db):
            raise HTTPException(status_code=403, detail="Access denied")
        
        return session_data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
