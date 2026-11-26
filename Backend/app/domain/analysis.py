"""Top-level analysis result and cross-object scientific invariants."""

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .cells import AcceptanceStatus, BIOLOGICAL_CLASS_ORDER, CellInstance
from .image_metadata import ImageMetadata
from .quality import QualityAssessment
from .spatial import SpatialMeasurements
from .tme import TMEAssessment, TMEState
from .tumor import TumorAssessment, TumorStatus


class AnalysisStatus(str, Enum):
    QUEUED = "QUEUED"
    RUNNING = "RUNNING"
    COMPLETE = "COMPLETE"
    FAILED = "FAILED"


class ModelMetadata(BaseModel):
    model_name: str
    model_version: str
    framework: str
    architecture: str
    checkpoint_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    class_order: tuple[str, str, str, str, str]

    @model_validator(mode="after")
    def validate_class_order(self):
        if tuple(name.upper() for name in self.class_order) != BIOLOGICAL_CLASS_ORDER:
            raise ValueError("model class order does not match the V2 biological binding")
        return self


class AnalysisOutput(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    analysis_run_id: str
    session_id: str
    status: AnalysisStatus
    stage: str = "COMPLETE"
    progress: float = Field(default=1.0, ge=0, le=1)
    image_metadata: ImageMetadata
    quality: QualityAssessment
    model_metadata: ModelMetadata
    cell_counts: dict[str, int]
    accepted_cell_counts: dict[str, int]
    uncertain_cell_counts: dict[str, int]
    cells_summary: list[CellInstance] = Field(default_factory=list)
    tumor_assessment: TumorAssessment
    spatial_measurements: Optional[SpatialMeasurements] = None
    tme_assessment: TMEAssessment
    warnings: list[str] = Field(default_factory=list)
    artifacts: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime
    completed_at: Optional[datetime] = None

    @model_validator(mode="after")
    def validate_scientific_state(self):
        if not self.image_metadata.scale_trusted:
            for cell in self.cells_summary:
                if (
                    cell.centroid_x_um is not None
                    or cell.centroid_y_um is not None
                    or cell.area_um2 is not None
                ):
                    raise ValueError("physical cell coordinates require trusted scale")
            if self.spatial_measurements is not None:
                raise ValueError("physical spatial measurements require trusted scale")

        state = self.tme_assessment.state
        tumor_status = self.tumor_assessment.status
        physical_states = {
            TMEState.HOT.value,
            TMEState.COLD.value,
            TMEState.EXCLUDED.value,
        }
        if state in physical_states and tumor_status != TumorStatus.PRESENT.value:
            raise ValueError(f"{state} requires confirmed PRESENT tumor context")
        if tumor_status == TumorStatus.ABSENT.value and state != TMEState.NOT_APPLICABLE.value:
            raise ValueError("ABSENT tumor context requires NOT_APPLICABLE TME")

        accepted = sum(
            1
            for cell in self.cells_summary
            if cell.acceptance_status == AcceptanceStatus.ACCEPTED.value
        )
        uncertain = sum(
            1
            for cell in self.cells_summary
            if cell.acceptance_status == AcceptanceStatus.UNCERTAIN.value
        )
        if accepted > sum(self.accepted_cell_counts.values()):
            raise ValueError("accepted cell summary exceeds accepted count totals")
        if uncertain > sum(self.uncertain_cell_counts.values()):
            raise ValueError("uncertain cell summary exceeds uncertain count totals")
        return self
