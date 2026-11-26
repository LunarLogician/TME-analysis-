from fastapi import APIRouter, Depends, HTTPException, status, Request
from uuid import UUID
from typing import List, Optional
from app.models.schemas import PatientCreate, PatientUpdate, PatientResponse, SessionResponse
from app.db.supabase_client import get_supabase_client
from supabase import Client
from gotrue.errors import AuthApiError
from app.utils.logging import get_logger
from app.middleware.auth import require_clinician, require_auth, AuthUser
from app.middleware.rate_limit import limiter
from app.utils.access_control import verify_patient_access

logger = get_logger(__name__)
router = APIRouter()


def _ensure_staff_profile(db: Client, user: AuthUser) -> None:
    """Backfill profiles for accounts created directly through Supabase Auth."""
    existing = db.table("users").select("id").eq("id", user.user_id).execute()
    if existing.data:
        return
    display_name = user.email.split("@", 1)[0].replace(".", " ").title()
    db.table("users").insert({
        "id": user.user_id,
        "email": user.email,
        "full_name": display_name or "Clinician",
        "role": "admin" if user.is_admin() else "clinician",
    }).execute()


def _extract_user_id(auth_obj: object) -> Optional[str]:
    if auth_obj is None:
        return None
    if hasattr(auth_obj, "id"):
        return getattr(auth_obj, "id")
    user = getattr(auth_obj, "user", None)
    if isinstance(user, dict):
        return user.get("id")
    if hasattr(user, "id"):
        return getattr(user, "id")
    if isinstance(auth_obj, dict):
        return auth_obj.get("id") or auth_obj.get("user", {}).get("id")
    return None


def _create_patient_user(db: Client, email: str, password: str, full_name: str) -> str:
    created = db.auth.admin.create_user({
        "email": email,
        "password": password,
        "user_metadata": {"full_name": full_name, "role": "patient"},
        "email_confirm": True,
    })
    user_id = _extract_user_id(created)
    if not user_id:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to create patient user account")

    try:
        db.table("users").insert({
            "id": user_id,
            "email": email,
            "full_name": full_name,
            "role": "patient",
        }).execute()
    except Exception:
        logger.warning("users table insert failed for new patient user; may already exist")
    return user_id


@router.post("/", response_model=PatientResponse, status_code=201)
@limiter.limit("10/minute")
async def create_patient(
    request: Request,
    patient: PatientCreate,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client)
):
    """Create a new patient record"""
    try:
        _ensure_staff_profile(db, user)
        insert_data = {
            "clinician_id": user.user_id,
            "full_name": patient.full_name,
            "date_of_birth": patient.date_of_birth,
            "gender": patient.gender,
            "diagnosis": patient.diagnosis,
        }

        # Optionally create or link a patient user account
        if patient.patient_email and patient.patient_password:
            if patient.patient_user_id is not None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot specify both patient_user_id and patient account creation fields"
                )
            insert_data["patient_user_id"] = _create_patient_user(
                db,
                email=patient.patient_email,
                password=patient.patient_password,
                full_name=patient.full_name,
            )
        elif patient.patient_user_id is not None:
            insert_data["patient_user_id"] = str(patient.patient_user_id)

        response = db.table("patients").insert(insert_data).execute()

        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=400, detail="Failed to create patient")
    except AuthApiError as auth_err:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(auth_err))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/", response_model=List[PatientResponse])
@limiter.limit("30/minute")
async def list_patients(
    request: Request,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client)
):
    """List all patients (clinicians see assigned patients; patients see themselves)"""
    try:
        if user.is_patient():
            response = db.table("patients").select("*").eq("patient_user_id", user.user_id).execute()
        elif user.is_admin():
            response = db.table("patients").select("*").execute()
        else:
            # Clinician: scoped to their own patients
            response = db.table("patients").select("*").eq("clinician_id", user.user_id).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{patient_id}", response_model=PatientResponse)
@limiter.limit("30/minute")
async def get_patient(
    request: Request,
    patient_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client)
):
    """Get single patient details"""
    try:
        response = db.table("patients").select("*").eq(
            "id", str(patient_id)
        ).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="Patient not found")
        
        patient_data = response.data[0]
        
        if not user.is_admin() and not verify_patient_access(str(patient_id), user, db):
            raise HTTPException(status_code=403, detail="Access denied")
        
        return patient_data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/{patient_id}", response_model=PatientResponse)
@limiter.limit("10/minute")
async def update_patient(
    request: Request,
    patient_id: UUID,
    patient: PatientUpdate,
    user: AuthUser = Depends(require_clinician),
    db: Client = Depends(get_supabase_client)
):
    """Update patient information"""
    try:
        existing = db.table("patients").select("*").eq(
            "id", str(patient_id)
        ).execute()
        
        if not existing.data:
            raise HTTPException(status_code=404, detail="Patient not found")
        
        patient_data = existing.data[0]
        if not user.is_admin() and patient_data["clinician_id"] != user.user_id:
            raise HTTPException(status_code=403, detail="Access denied")
        
        update_data = patient.model_dump(exclude_unset=True)
        
        response = db.table("patients").update(update_data).eq(
            "id", str(patient_id)
        ).execute()
        
        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=404, detail="Failed to update patient")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{patient_id}/sessions", response_model=List[SessionResponse])
@limiter.limit("30/minute")
async def get_patient_sessions(
    request: Request,
    patient_id: UUID,
    user: AuthUser = Depends(require_auth),
    db: Client = Depends(get_supabase_client)
):
    """Get all biopsy sessions for a patient (for trend graphs and history view)"""
    try:
        if not verify_patient_access(str(patient_id), user, db):
            raise HTTPException(status_code=403, detail="Access denied")
        
        response = db.table("biopsy_sessions").select("*").eq(
            "patient_id", str(patient_id)
        ).order("session_date", desc=True).execute()
        
        return response.data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
