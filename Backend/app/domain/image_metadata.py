"""Source-image metadata and explicit physical-scale trust."""

from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ScaleSource(str, Enum):
    WSI_METADATA = "WSI_METADATA"
    TIFF_METADATA = "TIFF_METADATA"
    USER_PROVIDED = "USER_PROVIDED"
    MAGNIFICATION_POLICY = "MAGNIFICATION_POLICY"
    UNKNOWN = "UNKNOWN"


class ImageMetadata(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    asset_id: str
    original_filename: str
    mime_type: str
    width_px: int = Field(gt=0)
    height_px: int = Field(gt=0)
    channels: int = Field(gt=0)
    bit_depth: Optional[int] = Field(default=None, gt=0)
    scanner: Optional[str] = None
    source_mpp_x: Optional[float] = Field(default=None, gt=0)
    source_mpp_y: Optional[float] = Field(default=None, gt=0)
    source_magnification: Optional[float] = Field(default=None, gt=0)
    effective_mpp_x: Optional[float] = Field(default=None, gt=0)
    effective_mpp_y: Optional[float] = Field(default=None, gt=0)
    effective_magnification: Optional[float] = Field(default=None, gt=0)
    scale_source: ScaleSource = ScaleSource.UNKNOWN
    scale_trusted: bool = False
    checksum_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")

    @model_validator(mode="after")
    def validate_scale(self):
        if self.scale_trusted and (
            self.source_mpp_x is None or self.source_mpp_y is None
        ):
            raise ValueError("trusted scale requires source_mpp_x and source_mpp_y")
        if self.scale_source == ScaleSource.UNKNOWN.value and self.scale_trusted:
            raise ValueError("UNKNOWN scale cannot be trusted")
        if not self.scale_trusted and (
            self.effective_mpp_x is not None or self.effective_mpp_y is not None
        ):
            raise ValueError("untrusted scale cannot expose effective physical scale")
        return self
