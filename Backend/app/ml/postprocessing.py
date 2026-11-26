"""Bundle-configured watershed reconstruction and 132-D instance typing."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Sequence

import cv2
import numpy as np
import torch
from scipy import ndimage as ndi
from skimage.measure import label, regionprops
from skimage.morphology import binary_dilation, binary_opening, disk, remove_small_objects
from skimage.segmentation import relabel_sequential, watershed

from app.domain.cells import AcceptanceStatus

from .predictor import DenseOutputs
from .tiling import Tile


def _sigmoid(values: np.ndarray) -> np.ndarray:
    values = np.clip(values, -80.0, 80.0)
    return 1.0 / (1.0 + np.exp(-values))


def _softmax(values: np.ndarray, axis: int) -> np.ndarray:
    shifted = values - np.max(values, axis=axis, keepdims=True)
    exp = np.exp(shifted)
    return exp / np.sum(exp, axis=axis, keepdims=True)


@dataclass
class LocalInstance:
    local_instance_id: str
    tile_id: str
    tile_origin_x: int
    tile_origin_y: int
    tile_width: int
    tile_height: int
    mask: np.ndarray
    centroid_x: float
    centroid_y: float
    area_px: int
    bbox_xyxy: tuple[int, int, int, int]
    segmentation_confidence: float
    descriptor: np.ndarray
    pixel_probabilities: np.ndarray
    fused_probabilities: np.ndarray | None = None
    calibrated_probabilities: np.ndarray | None = None
    class_id: int | None = None
    class_name: str | None = None
    class_confidence: float | None = None
    normalized_entropy: float | None = None
    top1_top2_margin: float | None = None
    acceptance_status: AcceptanceStatus | None = None

    @property
    def global_centroid(self) -> tuple[float, float]:
        return (
            self.tile_origin_x + self.centroid_x,
            self.tile_origin_y + self.centroid_y,
        )

    @property
    def global_bbox(self) -> tuple[float, float, float, float]:
        x1, y1, x2, y2 = self.bbox_xyxy
        return (
            self.tile_origin_x + x1,
            self.tile_origin_y + y1,
            self.tile_origin_x + x2,
            self.tile_origin_y + y2,
        )

    @property
    def touches_tile_border(self) -> bool:
        x1, y1, x2, y2 = self.bbox_xyxy
        return x1 <= 1 or y1 <= 1 or x2 >= self.tile_width - 1 or y2 >= self.tile_height - 1

    def global_pixels(self) -> set[tuple[int, int]]:
        ys, xs = np.nonzero(self.mask)
        return {
            (int(y + self.tile_origin_y), int(x + self.tile_origin_x))
            for y, x in zip(ys, xs)
        }


class InstancePostprocessor:
    def __init__(self, config: dict):
        self.config = config
        descriptor_config = config["instance_descriptor"]
        self.descriptor_dim = int(descriptor_config["descriptor_dim"])
        if self.descriptor_dim != 132:
            raise ValueError("The V2 instance descriptor must be 132-D")

    def reconstruct(
        self,
        dense: DenseOutputs,
        tiles: Sequence[Tile],
    ) -> list[LocalInstance]:
        if len(tiles) != dense.batch_size:
            raise ValueError("tile and dense-output batches are not aligned")
        np_logits = dense.np_logits.numpy()
        hv_maps = dense.hv_map.numpy()
        nt_logits = dense.nt_logits.numpy()
        contour_logits = dense.contour_logits.numpy()
        seed_logits = dense.seed_logits.numpy()
        feature_maps = dense.feature_map.numpy()
        global_contexts = dense.global_context.numpy()
        local_instances: list[LocalInstance] = []
        for index, tile in enumerate(tiles):
            np_probability = _softmax(np_logits[index], axis=0)[1]
            nt_probabilities = _softmax(nt_logits[index], axis=0)
            seed_probability = _sigmoid(seed_logits[index, 0])
            contour_probability = _sigmoid(contour_logits[index, 0])
            labels = self._reconstruct_labels(
                np_probability,
                seed_probability,
                hv_maps[index],
                contour_probability,
                tile,
            )
            for region in regionprops(labels):
                mask = labels == region.label
                descriptor = self._build_descriptor(
                    mask,
                    feature_maps[index],
                    global_contexts[index],
                )
                pixel_probability = nt_probabilities[:, mask].mean(axis=1)
                pixel_probability = pixel_probability / pixel_probability.sum()
                min_y, min_x, max_y, max_x = region.bbox
                local_instances.append(
                    LocalInstance(
                        local_instance_id=f"{tile.tile_id}-{region.label}",
                        tile_id=tile.tile_id,
                        tile_origin_x=tile.origin_x,
                        tile_origin_y=tile.origin_y,
                        tile_width=tile.valid_width,
                        tile_height=tile.valid_height,
                        mask=mask,
                        centroid_x=float(region.centroid[1]),
                        centroid_y=float(region.centroid[0]),
                        area_px=int(region.area),
                        # Regionprops uses an exclusive maximum; canonical bbox is inclusive.
                        bbox_xyxy=(min_x, min_y, max_x - 1, max_y - 1),
                        segmentation_confidence=float(np_probability[mask].mean()),
                        descriptor=descriptor,
                        pixel_probabilities=pixel_probability.astype(np.float32),
                    )
                )
        return local_instances

    def _reconstruct_labels(
        self,
        np_probability: np.ndarray,
        seed_probability: np.ndarray,
        hv_map: np.ndarray,
        contour_probability: np.ndarray,
        tile: Tile,
    ) -> np.ndarray:
        foreground = np_probability >= float(self.config["np_threshold"])
        foreground[tile.valid_height :, :] = False
        foreground[:, tile.valid_width :] = False
        if bool(self.config["morphology_open"]):
            foreground = binary_opening(
                foreground,
                footprint=disk(int(self.config["morphology_kernel"])),
            )
        foreground = remove_small_objects(
            foreground,
            min_size=int(self.config["min_nucleus_size"]),
            connectivity=2,
        )
        if not np.any(foreground):
            return np.zeros_like(foreground, dtype=np.int32)

        seed_mask = (seed_probability >= float(self.config["seed_threshold"])) & foreground
        seed_mask = remove_small_objects(
            seed_mask,
            min_size=int(self.config["marker_min_size"]),
            connectivity=2,
        )
        markers = label(seed_mask, connectivity=2)
        foreground_components = label(foreground, connectivity=2)
        next_marker = int(markers.max()) + 1
        # Conservative fallback: add exactly one marker only to a foreground
        # component in which the learned seed head produced no usable marker.
        for component_id in range(1, int(foreground_components.max()) + 1):
            component = foreground_components == component_id
            if np.any(markers[component] > 0):
                continue
            component_scores = np.where(component, seed_probability, -np.inf)
            y, x = np.unravel_index(np.argmax(component_scores), component_scores.shape)
            markers[y, x] = next_marker
            next_marker += 1

        h_energy = np.abs(cv2.Sobel(hv_map[0], cv2.CV_32F, 1, 0, ksize=3))
        v_energy = np.abs(cv2.Sobel(hv_map[1], cv2.CV_32F, 0, 1, ksize=3))
        hv_energy = np.maximum(h_energy, v_energy)
        maximum = float(hv_energy.max())
        if maximum > 0:
            hv_energy = hv_energy / maximum
        boundary = (
            float(self.config["hv_boundary_weight"]) * hv_energy
            + float(self.config["contour_weight"]) * contour_probability
        )
        reconstructed = watershed(boundary, markers=markers, mask=foreground)
        minimum_size = int(self.config["min_nucleus_size"])
        sizes = np.bincount(reconstructed.ravel())
        too_small = np.flatnonzero(sizes < minimum_size)
        too_small = too_small[too_small != 0]
        if too_small.size:
            reconstructed[np.isin(reconstructed, too_small)] = 0
        reconstructed, _, _ = relabel_sequential(reconstructed)
        return reconstructed.astype(np.int32, copy=False)

    def _build_descriptor(
        self,
        mask: np.ndarray,
        feature_map: np.ndarray,
        global_context: np.ndarray,
    ) -> np.ndarray:
        if feature_map.shape[0] != 32 or global_context.shape != (64,):
            raise ValueError("Dense features do not satisfy the V2 descriptor contract")
        interior = feature_map[:, mask].mean(axis=1)
        ring = binary_dilation(mask, footprint=disk(3)) & ~mask
        if np.any(ring):
            surrounding = feature_map[:, ring].mean(axis=1)
        else:
            surrounding = np.zeros(32, dtype=feature_map.dtype)
        ys, xs = np.nonzero(mask)
        height, width = mask.shape
        bbox_height = int(ys.max() - ys.min() + 1)
        bbox_width = int(xs.max() - xs.min() + 1)
        area = int(mask.sum())
        shape_features = np.asarray(
            [
                area / float(height * width),
                bbox_height / float(height),
                bbox_width / float(width),
                area / float(bbox_height * bbox_width),
            ],
            dtype=np.float32,
        )
        descriptor = np.concatenate(
            [interior, surrounding, global_context, shape_features], axis=0
        ).astype(np.float32, copy=False)
        if descriptor.shape != (self.descriptor_dim,):
            raise ValueError(
                f"Instance descriptor must be {self.descriptor_dim}-D, got {descriptor.shape}"
            )
        if not np.isfinite(descriptor).all():
            raise ValueError("Instance descriptor contains NaN or Inf")
        return descriptor

    def classify_and_fuse(
        self,
        instances: Sequence[LocalInstance],
        classifier: torch.jit.ScriptModule,
        *,
        device: torch.device | str,
    ) -> list[LocalInstance]:
        if not instances:
            return []
        descriptors = torch.from_numpy(
            np.stack([instance.descriptor for instance in instances], axis=0)
        ).to(device=device, dtype=torch.float32)
        with torch.inference_mode():
            logits = classifier(descriptors)
        if tuple(logits.shape) != (len(instances), 5):
            raise ValueError("Instance classifier must produce [B_instances,5]")
        if not torch.isfinite(logits).all():
            raise ValueError("Instance classifier produced NaN or Inf")
        instance_probabilities = torch.softmax(logits, dim=1).detach().cpu().numpy()
        blend = float(self.config["instance_head_blend"])
        for instance, instance_probability in zip(instances, instance_probabilities):
            fused = blend * instance_probability + (1.0 - blend) * instance.pixel_probabilities
            fused = np.clip(fused, 0.0, None)
            instance.fused_probabilities = (fused / fused.sum()).astype(np.float32)
        return list(instances)
