from fastapi import Request, status
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.middleware.base import BaseHTTPMiddleware
import logging
import traceback
from datetime import datetime
from app.utils.logging import get_logger, log_error, generate_request_id, set_request_id

logger = get_logger(__name__)


class AppError(Exception):
    """Base application error"""
    
    def __init__(self, message: str, status_code: int = 500, error_code: str = "INTERNAL_ERROR"):
        self.message = message
        self.status_code = status_code
        self.error_code = error_code
        super().__init__(self.message)


class ValidationError(AppError):
    """Request validation error"""
    
    def __init__(self, message: str):
        super().__init__(message, status_code=422, error_code="VALIDATION_ERROR")


class AuthenticationError(AppError):
    """Authentication failed"""
    
    def __init__(self, message: str = "Authentication failed"):
        super().__init__(message, status_code=401, error_code="AUTH_ERROR")


class AuthorizationError(AppError):
    """User not authorized for this action"""
    
    def __init__(self, message: str = "Insufficient permissions"):
        super().__init__(message, status_code=403, error_code="FORBIDDEN")


class NotFoundError(AppError):
    """Resource not found"""
    
    def __init__(self, resource: str):
        message = f"{resource} not found"
        super().__init__(message, status_code=404, error_code="NOT_FOUND")


class ConflictError(AppError):
    """Resource conflict (e.g., duplicate key)"""
    
    def __init__(self, message: str):
        super().__init__(message, status_code=409, error_code="CONFLICT")


class RateLimitError(AppError):
    """Rate limit exceeded"""
    
    def __init__(self, message: str = "Too many requests"):
        super().__init__(message, status_code=429, error_code="RATE_LIMIT_EXCEEDED")


class RequestIDMiddleware(BaseHTTPMiddleware):
    """Middleware to generate and attach request ID to all requests"""
    
    async def dispatch(self, request: Request, call_next):
        request_id = generate_request_id()
        set_request_id(request_id)
        request.state.request_id = request_id
        
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response


class ErrorHandlerMiddleware(BaseHTTPMiddleware):
    """Middleware to catch and format unhandled exceptions"""
    
    async def dispatch(self, request: Request, call_next):
        try:
            response = await call_next(request)
            return response
        
        except AppError as e:
            # Application-defined error
            log_error(
                e.error_code,
                e.message,
                {"path": request.url.path, "method": request.method},
                getattr(request.state, "user_id", None)
            )
            return JSONResponse(
                status_code=e.status_code,
                content={
                    "error": e.error_code,
                    "message": e.message,
                    "request_id": getattr(request.state, "request_id", "unknown"),
                    "timestamp": datetime.utcnow().isoformat()
                }
            )
        
        except RequestValidationError as e:
            # Pydantic validation error
            errors = []
            for error in e.errors():
                errors.append({
                    "field": ".".join(str(loc) for loc in error["loc"][1:]),
                    "message": error["msg"]
                })
            
            log_error(
                "VALIDATION_ERROR",
                "Request validation failed",
                {"errors": errors},
                getattr(request.state, "user_id", None)
            )
            return JSONResponse(
                status_code=422,
                content={
                    "error": "VALIDATION_ERROR",
                    "message": "Request validation failed",
                    "details": errors,
                    "request_id": getattr(request.state, "request_id", "unknown"),
                    "timestamp": datetime.utcnow().isoformat()
                }
            )
        
        except Exception as e:
            # Unhandled exception
            logger.exception(f"Unhandled exception: {str(e)}")
            log_error(
                "INTERNAL_ERROR",
                str(e),
                {"traceback": traceback.format_exc()},
                getattr(request.state, "user_id", None)
            )
            
            return JSONResponse(
                status_code=500,
                content={
                    "error": "INTERNAL_ERROR",
                    "message": "An unexpected error occurred",
                    "request_id": getattr(request.state, "request_id", "unknown"),
                    "timestamp": datetime.utcnow().isoformat()
                }
            )


class LoggingMiddleware(BaseHTTPMiddleware):
    """Middleware to log all requests and responses"""
    
    async def dispatch(self, request: Request, call_next):
        from time import time
        
        start_time = time()
        response = await call_next(request)
        process_time = (time() - start_time) * 1000  # Convert to ms
        
        logger.info(
            f"{request.method} {request.url.path} - Status: {response.status_code} - Duration: {process_time:.2f}ms"
        )
        
        return response
