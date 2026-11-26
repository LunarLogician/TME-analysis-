"""Localized TME-Nuclei V2 inference components."""

from .calibration import ConfidenceCalibrator
from .model_manager import BundleValidationError, ModelManager
from .postprocessing import InstancePostprocessor, LocalInstance
from .predictor import DenseOutputs, NucleiPredictor
from .preprocessing import ScaleResolver, SourceTransform
from .stitching import InstanceStitcher
from .tiling import Tile, TileGenerator

__all__ = [
    "BundleValidationError",
    "ConfidenceCalibrator",
    "DenseOutputs",
    "InstancePostprocessor",
    "InstanceStitcher",
    "LocalInstance",
    "ModelManager",
    "NucleiPredictor",
    "ScaleResolver",
    "SourceTransform",
    "Tile",
    "TileGenerator",
]
