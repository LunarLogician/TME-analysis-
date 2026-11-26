"""Pathologist-assisted tumor-context contracts."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


class TumorStatus(str, Enum):
    PRESENT = "PRESENT"
    ABSENT = "ABSENT"
    INDETERMINATE = "INDETERMINATE"


class TumorEvidenceSource(str, Enum):
    CLINICIAN_CONFIRMED_TUMOR = "CLINICIAN_CONFIRMED_TUMOR"
    CLINICIAN_CONFIRMED_NO_TUMOR = "CLINICIAN_CONFIRMED_NO_TUMOR"
    UNCONFIRMED_NUCLEI_ONLY = "UNCONFIRMED_NUCLEI_ONLY"
    VALIDATED_AI_TUMOR_GATE = "VALIDATED_AI_TUMOR_GATE"


class TumorRegionMode(str, Enum):
    WHOLE_ROI = "WHOLE_ROI"
    ANNOTATED_REGION = "ANNOTATED_REGION"
    NONE = "NONE"


class TumorAssessment(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    status: TumorStatus
    evidence_source: TumorEvidenceSource
    confirmed_by_user_id: Optional[str] = None
    confirmed_at: Optional[datetime] = None
    tumor_region_mode: Optional[TumorRegionMode] = None
    tumor_region_artifact_id: Optional[str] = None
    confident_neoplastic_count: int = Field(default=0, ge=0)
    uncertain_neoplastic_count: int = Field(default=0, ge=0)
    neoplastic_density_mm2: Optional[float] = Field(default=None, ge=0)
    spatial_coherence_score: Optional[float] = Field(default=None, ge=0, le=1)
    reason_codes: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_provenance(self):
        human_sources = {
            TumorEvidenceSource.CLINICIAN_CONFIRMED_TUMOR.value,
            TumorEvidenceSource.CLINICIAN_CONFIRMED_NO_TUMOR.value,
        }
        if self.evidence_source in human_sources and (
            not self.confirmed_by_user_id or not self.confirmed_at
        ):
            raise ValueError("clinician-confirmed tumor context requires user and time")
        if self.evidence_source == TumorEvidenceSource.CLINICIAN_CONFIRMED_TUMOR.value:
            if self.status != TumorStatus.PRESENT.value:
                raise ValueError("confirmed tumor evidence requires PRESENT status")
        if self.evidence_source == TumorEvidenceSource.CLINICIAN_CONFIRMED_NO_TUMOR.value:
            if self.status != TumorStatus.ABSENT.value:
                raise ValueError("confirmed no-tumor evidence requires ABSENT status")
        if self.evidence_source == TumorEvidenceSource.UNCONFIRMED_NUCLEI_ONLY.value:
            if self.status != TumorStatus.INDETERMINATE.value:
                raise ValueError("unconfirmed nuclei-only context must remain INDETERMINATE")
        return self
