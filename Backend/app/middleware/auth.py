import os
from typing import Optional
from functools import wraps
from fastapi import Request, HTTPException, Depends, status
from jose import JWTError, jwt
from app.utils.logging import get_logger, log_security_event

logger = get_logger(__name__)

# Get Supabase config from environment
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
# JWT secret for signature verification (Settings → API → JWT Secret in Supabase dashboard)
# If not set, falls back to unverified claims (dev-mode only — never do this in production)
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")


class AuthUser:
    """Represents an authenticated user context"""
    
    def __init__(self, user_id: str, email: str, role: str):
        self.user_id = user_id
        self.email = email
        self.role = role
    
    def is_admin(self) -> bool:
        return self.role == "admin"
    
    def is_clinician(self) -> bool:
        return self.role == "clinician"
    
    def is_patient(self) -> bool:
        return self.role == "patient"


async def extract_user_from_token(request: Request) -> Optional[AuthUser]:
    """
    Extract and validate JWT token from Authorization header.
    Returns AuthUser if valid, None if no token.
    """
    auth_header = request.headers.get("Authorization")
    
    if not auth_header:
        return None
    
    try:
        # Format: "Bearer <token>"
        if not auth_header.startswith("Bearer "):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authorization header format"
            )
        
        token = auth_header.split(" ")[1]
        
        # --- JWT Verification ---
        # If SUPABASE_JWT_SECRET is configured, perform full signature verification (recommended for production).
        # If not set, fall back to unverified claims (acceptable for local development only).
        if SUPABASE_JWT_SECRET:
            try:
                payload = jwt.decode(
                    token,
                    SUPABASE_JWT_SECRET,
                    algorithms=["HS256"],
                    options={"verify_aud": False}  # Supabase tokens don't use aud by default
                )
            except JWTError:
                log_security_event("JWT_VERIFICATION_FAILED", {"reason": "bad_signature"})
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid or tampered token"
                )
        else:
            if os.getenv("ENV", "development").strip().lower() == "production":
                log_security_event(
                    "JWT_CONFIGURATION_ERROR", {"reason": "missing_verification_secret"}
                )
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="JWT verification is not configured",
                )
            # Explicitly development-only fallback.
            logger.warning(
                "SUPABASE_JWT_SECRET not set — JWT signature NOT verified. "
                "Set this env var before deploying to production."
            )
            payload = jwt.get_unverified_claims(token)
        
        # Extract user info from JWT payload
        user_id = payload.get("sub")
        email = payload.get("email")
        
        # --- Role Extraction ---
        # Supabase stores admin-managed roles in app_metadata (set via Admin API).
        # user_metadata is self-reported by the user at signup — check app_metadata first.
        app_meta = payload.get("app_metadata", {}) or {}
        user_meta = payload.get("user_metadata", {}) or {}
        role = app_meta.get("role") or user_meta.get("role", "clinician")
        
        if not user_id or not email:
            log_security_event("INVALID_TOKEN", {"reason": "missing_claims"})
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token claims"
            )
        
        return AuthUser(user_id=user_id, email=email, role=role)
    
    except JWTError as e:
        logger.error(f"JWT validation error: {str(e)}")
        log_security_event("JWT_ERROR", {"error": str(e)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )
    except Exception as e:
        logger.error(f"Token extraction error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed"
        )


async def require_auth(request: Request) -> AuthUser:
    """
    Dependency to require authentication on an endpoint.
    Raises 401 if no valid token.
    """
    user = await extract_user_from_token(request)
    
    if user is None:
        log_security_event("MISSING_TOKEN", {"path": request.url.path})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )
    
    # Attach user to request for logging
    request.state.user = user
    return user


async def require_role(role: str):
    """
    Dependency factory to require specific role on an endpoint.
    Usage: Depends(require_role("admin"))
    """
    async def _require_role(user: AuthUser = Depends(require_auth)) -> AuthUser:
        if user.role != role:
            log_security_event(
                "INSUFFICIENT_ROLE",
                {"user_id": user.user_id, "required_role": role, "user_role": user.role}
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"This action requires {role} role"
            )
        return user
    
    return _require_role


async def require_admin(user: AuthUser = Depends(require_auth)) -> AuthUser:
    """Convenience dependency to require admin role"""
    if not user.is_admin():
        log_security_event(
            "INSUFFICIENT_ROLE",
            {"user_id": user.user_id, "required_role": "admin"}
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return user


async def require_clinician(user: AuthUser = Depends(require_auth)) -> AuthUser:
    """Convenience dependency to require clinician or admin role"""
    if not (user.is_clinician() or user.is_admin()):
        log_security_event(
            "INSUFFICIENT_ROLE",
            {"user_id": user.user_id, "required_role": "clinician"}
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Clinician access required"
        )
    return user


async def require_patient(user: AuthUser = Depends(require_auth)) -> AuthUser:
    """Convenience dependency to require patient role"""
    if not user.is_patient():
        log_security_event(
            "INSUFFICIENT_ROLE",
            {"user_id": user.user_id, "required_role": "patient"}
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Patient access required"
        )
    return user


def optional_auth(func):
    """
    Decorator for endpoints that work with or without auth.
    User context available if authenticated, None if not.
    """
    @wraps(func)
    async def wrapper(request: Request, *args, **kwargs):
        user = await extract_user_from_token(request)
        request.state.user = user
        return await func(request, *args, **kwargs)
    
    return wrapper
