"""Persistence adapters for V2 analysis records."""

from .analysis_repository import AnalysisRepository, SupabaseAnalysisRepository

__all__ = ["AnalysisRepository", "SupabaseAnalysisRepository"]
