"""Cell-level biological and review-state contracts."""

from enum import Enum, IntEnum
from typing import Annotated, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


class BiologicalClass(IntEnum):
    """Binding order exported by the V2 bundle."""

    NEOPLASTIC = 1
    INFLAMMATORY = 2
    CONNECTIVE = 3
    DEAD = 4
    EPITHELIAL = 5


BIOLOGICAL_CLASS_ORDER = tuple(member.name for member in BiologicalClass)


class AcceptanceStatus(str, Enum):
    ACCEPTED = "ACCEPTED"
    UNCERTAIN = "UNCERTAIN"
    REJECTED = "REJECTED"


Probability = Annotated[float, Field(ge=0.0, le=1.0)]


class CellInstance(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    instance_id: str
    class_id: BiologicalClass
    class_name: str
    centroid_x_px: float
    centroid_y_px: float
    centroid_x_um: Optional[float] = None
    centroid_y_um: Optional[float] = None
    area_px: float = Field(gt=0)
    area_um2: Optional[float] = Field(default=None, gt=0)
    bbox_xyxy: tuple[float, float, float, float]
    class_probabilities: tuple[
        Probability, Probability, Probability, Probability, Probability
    ]
    class_confidence: Probability
    normalized_entropy: Probability
    top1_top2_margin: Probability
    segmentation_confidence: Optional[Probability] = None
    acceptance_status: AcceptanceStatus
    source_tile_ids: list[str] = Field(min_length=1)
    tumor_membership: Optional[bool] = None

    @model_validator(mode="after")
    def validate_binding(self):
        expected_name = BiologicalClass(int(self.class_id)).name
        if self.class_name.upper() != expected_name:
            raise ValueError(
                f"class_id {self.class_id} is bound to {expected_name}, "
                f"not {self.class_name}"
            )
        probability_sum = sum(self.class_probabilities)
        if abs(probability_sum - 1.0) > 1e-5:
            raise ValueError("class_probabilities must sum to 1")
        x1, y1, x2, y2 = self.bbox_xyxy
        if x2 < x1 or y2 < y1:
            raise ValueError("bbox_xyxy must be ordered as x1,y1,x2,y2")
        return self
