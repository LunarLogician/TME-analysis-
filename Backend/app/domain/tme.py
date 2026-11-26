"""Canonical, non-coercible TME assessment states."""

from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


class TMEState(str, Enum):
    HOT = "HOT"
    COLD = "COLD"
    EXCLUDED = "EXCLUDED"
    INDETERMINATE = "INDETERMINATE"
    NOT_ASSESSABLE = "NOT_ASSESSABLE"
    NOT_APPLICABLE = "NOT_APPLICABLE"


class TMEAssessment(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    state: TMEState
    policy_version: str
    score: Optional[float] = Field(default=None, ge=0, le=1)
    reason_codes: list[str] = Field(default_factory=list)
    input_measurement_version: str

    @model_validator(mode="after")
    def validate_reason(self):
        if self.state in {
            TMEState.INDETERMINATE.value,
            TMEState.NOT_ASSESSABLE.value,
            TMEState.NOT_APPLICABLE.value,
        } and not self.reason_codes:
            raise ValueError(f"{self.state} must carry at least one reason code")
        return self
