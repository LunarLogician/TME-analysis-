import logging
import uuid
from typing import Optional
from datetime import datetime
import json

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(request_id)s] - %(message)s'
)

logger = logging.getLogger(__name__)


class RequestIDContextFilter(logging.Filter):
    """Add request ID to log records"""
    
    def __init__(self):
        super().__init__()
        self.request_id = None
    
    def filter(self, record):
        record.request_id = self.request_id or "unknown"
        return True


# Add filter to root logger
request_id_filter = RequestIDContextFilter()
for handler in logging.root.handlers:
    handler.addFilter(request_id_filter)


def get_logger(name: str) -> logging.LoggerAdapter:
    """Get a logger with request ID context"""
    return logging.getLogger(name)


def set_request_id(request_id: str):
    """Set the current request ID for logging"""
    request_id_filter.request_id = request_id


def generate_request_id() -> str:
    """Generate a unique request ID"""
    return f"{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:8]}"


def log_request(method: str, path: str, status_code: int, duration_ms: float, user_id: Optional[str] = None):
    """Log incoming request with details"""
    logger = get_logger(__name__)
    logger.info(
        f"REQUEST {method} {path} - Status: {status_code} - Duration: {duration_ms:.2f}ms - User: {user_id or 'anonymous'}"
    )


def log_error(error_type: str, message: str, details: Optional[dict] = None, user_id: Optional[str] = None):
    """Log error with context"""
    logger = get_logger(__name__)
    extra = json.dumps(details) if details else ""
    logger.error(f"ERROR {error_type}: {message} {extra} - User: {user_id or 'anonymous'}")


def log_security_event(event: str, details: dict, user_id: Optional[str] = None):
    """Log security-related events"""
    logger = get_logger(__name__)
    logger.warning(f"SECURITY {event}: {json.dumps(details)} - User: {user_id or 'anonymous'}")
