"""Dense seven-head TorchScript inference with strict runtime validation."""

from __future__ import annotations

from dataclasses import dataclass
from time import perf_counter
from typing import Sequence

import torch

from .model_manager import BundleValidationError, ModelManager


@dataclass(frozen=True)
class DenseOutputs:
    np_logits: torch.Tensor
    hv_map: torch.Tensor
    nt_logits: torch.Tensor
    contour_logits: torch.Tensor
    seed_logits: torch.Tensor
    feature_map: torch.Tensor
    global_context: torch.Tensor
    inference_ms: float
    batch_size: int
    device: str
    peak_vram: int | None = None

    def tensors(self) -> tuple[torch.Tensor, ...]:
        return (
            self.np_logits,
            self.hv_map,
            self.nt_logits,
            self.contour_logits,
            self.seed_logits,
            self.feature_map,
            self.global_context,
        )


class NucleiPredictor:
    def __init__(self, manager: ModelManager):
        self.manager = manager

    def predict_batch(self, batch: torch.Tensor) -> DenseOutputs:
        patch_h, patch_w = self.manager.patch_size
        if batch.ndim != 4 or tuple(batch.shape[1:]) != (3, patch_h, patch_w):
            raise ValueError(
                f"V2 input must have shape [B,3,{patch_h},{patch_w}], got {tuple(batch.shape)}"
            )
        if not torch.isfinite(batch).all():
            raise ValueError("V2 input contains NaN or Inf")
        batch = batch.to(self.manager.device, dtype=torch.float32)
        if self.manager.device.type == "cuda":
            torch.cuda.reset_peak_memory_stats(self.manager.device)
        started = perf_counter()
        with torch.inference_mode():
            raw = self.manager.model(batch)
        inference_ms = (perf_counter() - started) * 1000
        if not isinstance(raw, (tuple, list)) or len(raw) != 7:
            raise BundleValidationError("Dense inference did not return seven outputs")
        self._validate_shapes(raw, batch.shape[0], patch_h, patch_w)
        if not all(torch.isfinite(tensor).all() for tensor in raw):
            raise BundleValidationError("Dense inference produced NaN or Inf")
        peak = (
            int(torch.cuda.max_memory_allocated(self.manager.device))
            if self.manager.device.type == "cuda"
            else None
        )
        cpu_outputs = tuple(tensor.detach().cpu() for tensor in raw)
        return DenseOutputs(
            *cpu_outputs,
            inference_ms=inference_ms,
            batch_size=int(batch.shape[0]),
            device=str(self.manager.device),
            peak_vram=peak,
        )

    @staticmethod
    def _validate_shapes(
        outputs: Sequence[torch.Tensor], batch: int, height: int, width: int
    ) -> None:
        expected = (
            (batch, 2, height, width),
            (batch, 2, height, width),
            (batch, 5, height, width),
            (batch, 1, height, width),
            (batch, 1, height, width),
            (batch, 32, height, width),
            (batch, 64),
        )
        actual = tuple(tuple(tensor.shape) for tensor in outputs)
        if actual != expected:
            raise BundleValidationError(
                f"Dense output shapes are invalid: expected {expected}, got {actual}"
            )
