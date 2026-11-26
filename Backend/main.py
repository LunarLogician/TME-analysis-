from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi.errors import RateLimitExceeded
from contextlib import asynccontextmanager
import os
from dotenv import load_dotenv
import logging

# Import routers
from app.routers import (
    analysis_v2,
    analytics,
    auth,
    patients,
    sessions,
)
from app.db.supabase_client import (
    close_supabase_client,
    create_supabase_service_client,
)
from app.middleware.error_handler import (
    ErrorHandlerMiddleware, RequestIDMiddleware, LoggingMiddleware,
    AppError
)
from app.middleware.rate_limit import limiter, rate_limit_error_handler
from app.ml.model_manager import ModelManager
from app.repositories.analysis_repository import SupabaseAnalysisRepository
from app.services.analysis_service import AnalysisService
from app.workers.queue import build_analysis_queue

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()


# ============= Lifespan Context =============
@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan context for startup/shutdown"""
    # Startup
    logger.info("Starting TME-Insight API...")
    if os.getenv("ENV", "development").lower() == "production" and not os.getenv(
        "SUPABASE_JWT_SECRET"
    ):
        raise RuntimeError("SUPABASE_JWT_SECRET is mandatory in production")
    cors_origins = [
        item.strip()
        for item in os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
        if item.strip()
    ]
    if os.getenv("ENV", "development").lower() == "production" and "*" in cors_origins:
        raise RuntimeError("Wildcard CORS is not permitted in production")

    logger.info("Loading checksum-verified TME-Insight model bundle...")
    app.state.model_manager = ModelManager()
    app.state.supabase = create_supabase_service_client()
    repository = SupabaseAnalysisRepository(app.state.supabase)
    app.state.analysis_service = AnalysisService(
        manager=app.state.model_manager,
        repository=repository,
    )
    app.state.analysis_queue = build_analysis_queue(
        app.state.analysis_service,
        development_service_factory=lambda: app.state.analysis_service.with_repository(
            SupabaseAnalysisRepository(create_supabase_service_client())
        ),
    )

    logger.info("✓ Application startup complete")
    
    yield
    
    # Shutdown
    logger.info("Shutting down TME-Insight API...")
    queue = getattr(app.state, "analysis_queue", None)
    if queue is not None:
        queue.shutdown()
    supabase = getattr(app.state, "supabase", None)
    if supabase is not None:
        close_supabase_client(supabase)
    logger.info("✓ Application shutdown complete")


# ============= FastAPI App =============
app = FastAPI(
    title="TME-Insight API",
    description="AI-Powered Clinical Decision Support System for Histopathology",
    version="2.0.0",
    lifespan=lifespan
)

# ============= Middleware Registration =============
# Order matters: logging should be first (outermost), then error handling, then request ID
app.add_middleware(LoggingMiddleware)
app.add_middleware(ErrorHandlerMiddleware)
app.add_middleware(RequestIDMiddleware)

# Add rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_error_handler)
app.add_exception_handler(AppError, lambda request, exc: exc)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "http://localhost:3000").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============= Health Check =============
@app.get("/health", tags=["Health"])
async def health_check():
    """Health check endpoint"""
    return {
        "status": "ok",
        "service": "TME-Insight API",
        "model_loaded": getattr(app.state, "model_manager", None) is not None,
        "model_name": getattr(
            getattr(app.state, "model_manager", None), "manifest", {}
        ).get("model_name"),
        "model_version": getattr(
            getattr(app.state, "model_manager", None), "manifest", {}
        ).get("model_version"),
        "device": str(getattr(getattr(app.state, "model_manager", None), "device", "unknown")),
        "inference_available": getattr(app.state, "model_manager", None) is not None,
        "analysis_queue": type(getattr(app.state, "analysis_queue", None)).__name__,
        "report_generation_available": True,
    }


# ============= Root Endpoint =============
@app.get("/", tags=["Root"])
async def root():
    """Root endpoint"""
    return {
        "title": "TME-Insight API",
        "version": "2.0.0",
        "status": "running"
    }


# ============= Include Routers =============
app.include_router(
    auth.router,
    tags=["Authentication"]
)

app.include_router(
    patients.router,
    prefix="/patients",
    tags=["Patients"]
)

app.include_router(
    sessions.router,
    prefix="/sessions",
    tags=["Sessions"]
)

app.include_router(
    analytics.router,
    prefix="/analytics",
    tags=["Analytics"]
)

app.include_router(
    analysis_v2.router,
    tags=["TME-Insight Analysis"],
)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
