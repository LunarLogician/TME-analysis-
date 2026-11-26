"""Physical-coordinate spatial measurement contract."""

from typing import Optional

from pydantic import BaseModel, Field


class SpatialMeasurements(BaseModel):
    measurement_version: str = "spatial-v2.0"
    neo_count_accepted: int = Field(ge=0)
    immune_count_accepted: int = Field(ge=0)
    class_counts_accepted: dict[str, int] = Field(default_factory=dict)
    class_counts_uncertain: dict[str, int] = Field(default_factory=dict)
    tissue_area_mm2: Optional[float] = Field(default=None, ge=0)
    tumor_area_mm2: Optional[float] = Field(default=None, ge=0)
    neo_density_mm2: Optional[float] = Field(default=None, ge=0)
    immune_density_mm2: Optional[float] = Field(default=None, ge=0)
    immune_to_neo_ratio: Optional[float] = Field(default=None, ge=0)
    neo_to_immune_mean_um: Optional[float] = Field(default=None, ge=0)
    neo_to_immune_median_um: Optional[float] = Field(default=None, ge=0)
    neo_to_immune_p25_um: Optional[float] = Field(default=None, ge=0)
    neo_to_immune_p75_um: Optional[float] = Field(default=None, ge=0)
    immune_to_neo_mean_um: Optional[float] = Field(default=None, ge=0)
    immune_to_neo_median_um: Optional[float] = Field(default=None, ge=0)
    intratumoral_immune_density_mm2: Optional[float] = Field(default=None, ge=0)
    peritumoral_immune_density_mm2: Optional[float] = Field(default=None, ge=0)
    boundary_infiltration_score: Optional[float] = Field(default=None, ge=0, le=1)
    measurement_warnings: list[str] = Field(default_factory=list)
