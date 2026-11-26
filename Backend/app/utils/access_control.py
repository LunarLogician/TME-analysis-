"""
Shared access control utilities.

Consolidates patient ownership checks used by patient, session, and analysis
routes.
"""
from supabase import Client
from app.middleware.auth import AuthUser


def verify_patient_access(patient_id: str, user: AuthUser, db: Client) -> bool:
    """
    Check whether the authenticated user is allowed to access a patient's data.

    Rules:
      - Admin users have universal access.
      - Clinicians can only access patients they created (clinician_id = user.user_id).
      - Patients can only access their own record (patient_user_id = user.user_id).

    Args:
        patient_id: UUID string of the target patient record.
        user:       The authenticated AuthUser context.
        db:         Active Supabase client.

    Returns:
        True if access is allowed, False otherwise.
    """
    if user.is_admin():
        return True

    query = db.table("patients").select("id").eq("id", str(patient_id))
    if user.is_patient():
        query = query.eq("patient_user_id", user.user_id)
    else:
        # Clinician
        query = query.eq("clinician_id", user.user_id)

    response = query.execute()
    return bool(response.data)
