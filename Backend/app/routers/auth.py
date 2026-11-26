from fastapi import APIRouter, HTTPException, Depends, status, Request
from typing import Optional, Dict, Any
from pydantic import BaseModel, EmailStr, Field, validator
from app.db.supabase_client import get_supabase_client
from supabase import Client
from gotrue.errors import AuthApiError
from app.utils.logging import get_logger, log_security_event
from app.middleware.error_handler import (
    AuthenticationError, ValidationError, ConflictError
)
from app.middleware.rate_limit import limiter
from app.middleware.auth import require_admin, AuthUser
import re
import os

logger = get_logger(__name__)

router = APIRouter(prefix="/auth", tags=["Auth"])


# ============= Helper Functions =============

def is_test_email(email: str) -> bool:
    """Check if email is a test/development email"""
    test_domains = ['test.com', 'fyp.com', 'example.com']
    return any(email.endswith(f'@{domain}') for domain in test_domains)


def is_dev_environment() -> bool:
    """Check if running in development mode"""
    return os.getenv("ENV", "development").lower() == "development"


# ============= Request/Response Models =============

class SignupRequest(BaseModel):
    email: EmailStr
    full_name: str = Field(..., min_length=3, max_length=100)
    password: str = Field(..., min_length=8, max_length=100)
    role: str = Field(default="clinician", pattern="^(clinician|patient)$")
    
    @validator('password')
    def validate_password(cls, v):
        """Validate password strength"""
        if not any(char.isupper() for char in v):
            raise ValueError('Password must contain at least one uppercase letter')
        if not any(char.isdigit() for char in v):
            raise ValueError('Password must contain at least one digit')
        if not any(char in '!@#$%^&*()_+-=[]{}|;:,.<>?' for char in v):
            raise ValueError('Password must contain at least one special character')
        return v
    
    @validator('full_name')
    def validate_full_name(cls, v):
        """Validate full name"""
        if not re.match(r'^[a-zA-Z\s]+$', v):
            raise ValueError('Full name can only contain letters and spaces')
        return v

    @validator('role')
    def validate_role(cls, v):
        if v not in ('clinician', 'patient'):
            raise ValueError('Invalid role, must be clinician or patient')
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict


class UserResponse(BaseModel):
    id: str
    email: str
    full_name: str
    role: str
    created_at: str


def _extract_user_id(auth_obj: Any) -> Optional[str]:
    if auth_obj is None:
        return None
    if isinstance(auth_obj, dict):
        if auth_obj.get("id"):
            return auth_obj["id"]
        user = auth_obj.get("user")
        if isinstance(user, dict):
            return user.get("id")
    else:
        if hasattr(auth_obj, "id"):
            return getattr(auth_obj, "id")
        user = getattr(auth_obj, "user", None)
        if isinstance(user, dict):
            return user.get("id")
        if hasattr(user, "id"):
            return getattr(user, "id")
    return None


def _extract_access_token(auth_obj: Any) -> Optional[str]:
    if auth_obj is None:
        return None
    if isinstance(auth_obj, dict):
        session = auth_obj.get("session")
        if isinstance(session, dict):
            return session.get("access_token")
        return auth_obj.get("access_token")
    if hasattr(auth_obj, "session") and getattr(auth_obj.session, "access_token", None):
        return auth_obj.session.access_token
    if hasattr(auth_obj, "access_token"):
        return getattr(auth_obj, "access_token")
    return None


def _admin_signup_fallback(db: Client, signup_data: SignupRequest, role: str) -> dict:
    created = db.auth.admin.create_user({
        "email": signup_data.email,
        "password": signup_data.password,
        "user_metadata": {
            "full_name": signup_data.full_name,
            "role": role,
        },
        "email_confirm": True,
    })

    user_id = _extract_user_id(created)
    if not user_id:
        raise AuthenticationError("Failed to create account via admin fallback")

    try:
        db.table("users").insert({
            "id": user_id,
            "email": signup_data.email,
            "full_name": signup_data.full_name,
            "role": role,
        }).execute()
    except Exception:
        logger.warning("users table insert failed for admin-created user; may already exist")

    token = None
    try:
        login_response = db.auth.sign_in_with_password({
            "email": signup_data.email,
            "password": signup_data.password,
        })
        token = _extract_access_token(login_response)
    except Exception:
        logger.info("Admin-created user could not sign in immediately; continuing without token")

    log_security_event(
        "SIGNUP_SUCCESS_ADMIN_FALLBACK",
        {"email": signup_data.email, "role": role}
    )

    return {
        "access_token": token or "",
        "token_type": "bearer",
        "user": {
            "id": user_id,
            "email": signup_data.email,
            "full_name": signup_data.full_name,
        }
    }


# ============= Authentication Endpoints =============

@router.post("/signup", response_model=TokenResponse, status_code=201)
@limiter.limit("3/hour")
async def signup(
    request: Request,
    signup_data: SignupRequest,
    db: Client = Depends(get_supabase_client)
):
    """
    Create a new user account.
    
    - Email must be unique
    - Password must be at least 8 characters with uppercase, digit, and special char
    - Role defaults to 'clinician'
    - Test emails (@test.com, @fyp.com) auto-verify; production emails send verification email
    
    Returns JWT token and user info.
    """
    try:
        # Check if email already exists
        existing = db.table("users").select("id").eq("email", signup_data.email).execute()
        if existing.data:
            log_security_event(
                "SIGNUP_DUPLICATE_EMAIL",
                {"email": signup_data.email}
            )
            raise ConflictError("Email already registered")

        role = signup_data.role or "clinician"

        auth_response = db.auth.sign_up({
            "email": signup_data.email,
            "password": signup_data.password,
            "options": {
                "data": {
                    "full_name": signup_data.full_name,
                    "role": role,
                }
            }
        })

        auth_user = getattr(auth_response, "user", None)
        if auth_user is None and isinstance(auth_response, dict):
            auth_user = auth_response.get("user")

        if not auth_user:
            raise AuthenticationError("Failed to create account")

        user_id = _extract_user_id(auth_user)
        if not user_id:
            raise AuthenticationError("Failed to retrieve user id after signup")

        db.table("users").insert({
            "id": user_id,
            "email": signup_data.email,
            "full_name": signup_data.full_name,
            "role": role,
        }).execute()

        is_test = is_test_email(signup_data.email)

        if is_test:
            try:
                db.auth.admin.update_user_by_id(
                    user_id,
                    {"email_confirm": True}
                )
                logger.info(f"Auto-confirmed test email for {signup_data.email}")
            except AuthApiError as admin_err:
                logger.warning(
                    f"Failed to auto-confirm test user {signup_data.email}: {admin_err.message}"
                )
            except Exception as admin_err:
                logger.warning(
                    f"Failed to auto-confirm test user {signup_data.email}: {str(admin_err)}"
                )

        token = _extract_access_token(auth_response)
        verification_sent = False

        if not token and is_test:
            try:
                login_response = db.auth.sign_in_with_password({
                    "email": signup_data.email,
                    "password": signup_data.password,
                })
                token = _extract_access_token(login_response)
                if token:
                    logger.info(f"Test user auto-verified and signed in: {signup_data.email}")
            except Exception:
                logger.info(f"Test user created but email verification required: {signup_data.email}")
                verification_sent = True
        elif not token:
            verification_sent = True
            logger.info(f"Production user created, verification email sent to: {signup_data.email}")

        log_security_event(
            "SIGNUP_SUCCESS",
            {
                "email": signup_data.email,
                "role": role,
                "is_test": is_test,
                "verification_sent": verification_sent,
            }
        )

        response_data = {
            "access_token": token or "",
            "token_type": "bearer",
            "user": {
                "id": user_id,
                "email": signup_data.email,
                "full_name": signup_data.full_name,
                "role": role,
            }
        }

        return response_data

    except ConflictError:
        raise
    except AuthenticationError:
        raise
    except AuthApiError as e:
        error_msg = str(e)
        logger.error(f"Signup auth error: {error_msg}")
        log_security_event(
            "SIGNUP_ERROR",
            {"email": signup_data.email, "error": error_msg, "code": e.code, "status": e.status}
        )

        is_test = is_test_email(signup_data.email)
        if (
            e.status == status.HTTP_429_TOO_MANY_REQUESTS
            or e.code in ("over_email_send_rate_limit", "over_request_rate_limit")
        ):
            if is_test or is_dev_environment():
                return _admin_signup_fallback(db, signup_data, signup_data.role or "clinician")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    "Supabase email rate limit exceeded. Wait a few minutes and try again, "
                    "or use an existing test account."
                ),
            )

        if e.code in ("email_exists", "user_already_exists"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered."
            )

        raise HTTPException(
            status_code=e.status if e.status and e.status < 500 else status.HTTP_400_BAD_REQUEST,
            detail=e.message,
        )
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Signup error: {error_msg}")
        log_security_event(
            "SIGNUP_ERROR",
            {"email": signup_data.email, "error": error_msg}
        )

        lower = error_msg.lower()
        if ("rate limit" in lower or "429" in lower) and (
            is_test_email(signup_data.email) or is_dev_environment()
        ):
            return _admin_signup_fallback(db, signup_data, signup_data.role or "clinician")

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Account creation failed"
        )


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login(
    request: Request,
    login_data: LoginRequest,
    db: Client = Depends(get_supabase_client)
):
    """
    Authenticate user with email and password.
    
    Returns JWT token and user info.
    """
    try:
        # Authenticate with Supabase
        auth_response = db.auth.sign_in_with_password({
            "email": login_data.email,
            "password": login_data.password
        })
        
        if not auth_response.session:
            log_security_event(
                "LOGIN_FAILED",
                {"email": login_data.email, "reason": "invalid_credentials"}
            )
            raise AuthenticationError("Invalid email or password")
        
        # Fetch user details from database
        user_response = db.table("users").select("*").eq(
            "email", login_data.email
        ).single().execute()
        
        if not user_response.data:
            raise AuthenticationError("User not found")
        
        user_data = user_response.data
        logger.info(f"User login successful: {login_data.email}")
        
        return TokenResponse(
            access_token=auth_response.session.access_token,
            user={
                "id": user_data["id"],
                "email": user_data["email"],
                "full_name": user_data["full_name"],
                "role": user_data["role"]
            }
        )
    
    except AuthenticationError:
        raise
    except AuthApiError as e:
        error_msg = str(e)
        logger.error(f"Login auth error: {error_msg}")
        log_security_event(
            "LOGIN_ERROR",
            {"email": login_data.email, "error": error_msg, "code": e.code, "status": e.status}
        )

        if e.code == "email_not_confirmed":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "Email not confirmed. "
                    "Use POST /auth/admin/confirm-email?email=<email> to confirm in dev, "
                    "or verify the link in your inbox."
                )
            )
        if e.status == status.HTTP_429_TOO_MANY_REQUESTS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many login attempts. Please wait and try again."
            )

        raise HTTPException(
            status_code=e.status if e.status and e.status < 500 else status.HTTP_400_BAD_REQUEST,
            detail=e.message,
        )
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Login error: {error_msg}")
        log_security_event(
            "LOGIN_ERROR",
            {"email": login_data.email, "error": error_msg}
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed"
        )


@router.get("/me", response_model=UserResponse)
async def get_current_user(
    request: Request,
    db: Client = Depends(get_supabase_client)
):
    """
    Get current authenticated user profile.
    Requires valid JWT token in Authorization header.
    """
    from app.middleware.auth import require_auth
    
    user = await require_auth(request)
    
    try:
        # Fetch full user details from database
        user_response = db.table("users").select("*").eq(
            "id", user.user_id
        ).single().execute()
        
        if not user_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        user_data = user_response.data
        return UserResponse(
            id=user_data["id"],
            email=user_data["email"],
            full_name=user_data["full_name"],
            role=user_data["role"],
            created_at=user_data["created_at"]
        )
    
    except Exception as e:
        logger.error(f"Get current user error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch user profile"
        )


@router.post("/logout")
async def logout(
    request: Request,
    db: Client = Depends(get_supabase_client)
):
    """
    Logout current user.
    Invalidates session on server side.
    """
    from app.middleware.auth import require_auth
    
    user = await require_auth(request)
    
    try:
        # Sign out with Supabase
        db.auth.sign_out()
        logger.info(f"User logout successful: {user.email}")
        
        return {
            "message": "Logged out successfully"
        }
    
    except Exception as e:
        logger.error(f"Logout error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Logout failed"
        )


@router.post("/admin/confirm-email")
@limiter.limit("10/minute")
async def admin_confirm_email(
    request: Request,
    email: str,
    db: Client = Depends(get_supabase_client)
):
    """
    DEV ENDPOINT: Instantly confirm a user's email using the Supabase Admin API.

    Only works with test emails (@test.com, @fyp.com, @example.com).
    Uses the service-role key to call auth.admin.update_user_by_email, which
    bypasses the normal email verification flow.

    In production, remove or restrict this endpoint behind an admin role.
    """
    if not is_test_email(email) and not is_dev_environment():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email confirmation endpoint only available in development or for test emails."
        )

    try:
        # Look up the user by email in our users table first
        user_response = db.table("users").select("id").eq("email", email).execute()
        if not user_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User '{email}' not found in users table."
            )

        user_id = user_response.data[0]["id"]

        # Use the Supabase Admin API to confirm the email
        # The admin client (service_role key) can update auth.users directly
        try:
            db.auth.admin.update_user_by_id(
                user_id,
                {"email_confirm": True}
            )
            logger.info(f"Email confirmed via admin API for user: {email} (id={user_id})")
            log_security_event("ADMIN_EMAIL_CONFIRMED", {"email": email, "user_id": user_id})
        except Exception as admin_err:
            logger.error(f"Admin confirm failed: {str(admin_err)}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Admin confirmation failed: {str(admin_err)}"
            )

        return {
            "message": f"Email '{email}' has been confirmed. You can now log in.",
            "user_id": user_id,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Email confirmation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Email confirmation failed."
        )


@router.get("/admin/users")
@limiter.limit("10/minute")
async def admin_list_users(
    request: Request,
    user: AuthUser = Depends(require_admin),
    db: Client = Depends(get_supabase_client)
):
    """
    List application users for the administrator directory.
    Excludes sensitive fields.
    """
    try:
        response = db.table("users").select("id, email, full_name, role, created_at").execute()
        return {
            "count": len(response.data),
            "users": response.data
        }
    except Exception as e:
        logger.error(f"Admin list users error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list users."
        )
