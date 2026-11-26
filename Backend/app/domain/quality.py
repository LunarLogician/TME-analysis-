"""Image quality contract."""

from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class QualityStatus(str, Enum):
    PASS = "PASS"
    WARNING = "WARNING"
    FAIL = "FAIL"


class QualityAssessment(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    status: QualityStatus
    blur_score: Optional[float] = Field(default=None, ge=0)
    tissue_fraction: float = Field(ge=0, le=1)
    background_fraction: float = Field(ge=0, le=1)
    exposure_score: Optional[float] = Field(default=None, ge=0, le=1)
    resolution_valid: bool
    scale_valid: bool
    he_stain_valid: Optional[bool] = None
    he_stain_score: Optional[float] = Field(default=None, ge=0, le=1)
    hematoxylin_fraction: Optional[float] = Field(default=None, ge=0, le=1)
    eosin_fraction: Optional[float] = Field(default=None, ge=0, le=1)
    stain_hue_fraction: Optional[float] = Field(default=None, ge=0, le=1)
    chromatic_tissue_fraction: Optional[float] = Field(default=None, ge=0, le=1)
    warnings: list[str] = Field(default_factory=list)
    failures: list[str] = Field(default_factory=list)
