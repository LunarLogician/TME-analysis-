from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request, status
from fastapi.responses import JSONResponse
from datetime import datetime
import os
from dotenv import load_dotenv

load_dotenv()

# Initialize rate limiter
limiter = Limiter(
    key_func=get_remote_address,
    enabled=os.getenv("RATE_LIMIT_ENABLED", "true").lower() == "true"
)


async def rate_limit_error_handler(request: Request, exc: RateLimitExceeded):
    """Custom error handler for rate limit exceeded"""
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={
            "error": "RATE_LIMIT_EXCEEDED",
            "message": "Too many requests. Please try again later.",
            "request_id": getattr(request.state, "request_id", "unknown"),
            "timestamp": datetime.utcnow().isoformat()
        }
    )


# Rate limit configurations
RATE_LIMITS = {
    "auth_login": "5/minute",          # 5 login attempts per minute
    "auth_signup": "3/hour",           # 3 signup attempts per hour
    "auth_password_reset": "3/hour",   # 3 password resets per hour
    "analysis": "1/hour",              # 1 analysis per hour per user
    "default": "100/minute",           # Default limit: 100 requests per minute
}
