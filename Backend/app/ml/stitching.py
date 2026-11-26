"""Cross-tile duplicate reconciliation and global/source coordinates."""

from __future__ import annotations

from dataclasses import dataclass
from math import hypot
from typing import Sequence
from uuid import NAMESPACE_URL, uuid5

import numpy as np

from app.domain.cells import CellInstance

from .calibration import ConfidenceCalibrator
from .postprocessing import LocalInstance
from .preprocessing import SourceTransform


class _DisjointSet:
    def __init__(self, size: int):
        self.parent = list(range(size))

    def find(self, item: int) -> int:
        while self.parent[item] != item:
            self.parent[item] = self.parent[self.parent[item]]
            item = self.parent[item]
        return item

    def union(self, left: int, right: int) -> None:
        left_root, right_root = self.find(left), self.find(right)
        if left_root != right_root:
            self.parent[right_root] = left_root


class InstanceStitcher:
    def __init__(
        self,
        calibrator: ConfidenceCalibrator,
        *,
        minimum_mask_iou: float = 0.20,
        maximum_border_centroid_distance: float = 3.0,
    ):
        self.calibrator = calibrator
        self.minimum_mask_iou = float(minimum_mask_iou)
        self.maximum_border_centroid_distance = float(maximum_border_centroid_distance)

    @staticmethod
    def _bbox_intersects(
        left: tuple[float, float, float, float],
        right: tuple[float, float, float, float],
    ) -> bool:
        return not (
            left[2] < right[0]
            or right[2] < left[0]
            or left[3] < right[1]
            or right[3] < left[1]
        )

    @staticmethod
    def _mask_iou(left: LocalInstance, right: LocalInstance) -> float:
        left_pixels = left.global_pixels()
        right_pixels = right.global_pixels()
        intersection = len(left_pixels & right_pixels)
        if intersection == 0:
            return 0.0
        return intersection / float(len(left_pixels | right_pixels))

    def _duplicates(self, left: LocalInstance, right: LocalInstance) -> bool:
        if left.tile_id == right.tile_id:
            return False
        if not self._bbox_intersects(left.global_bbox, right.global_bbox):
            return False
        if self._mask_iou(left, right) >= self.minimum_mask_iou:
            return True
        left_x, left_y = left.global_centroid
        right_x, right_y = right.global_centroid
        return (
            left.touches_tile_border
            and right.touches_tile_border
            and hypot(left_x - right_x, left_y - right_y)
            <= self.maximum_border_centroid_distance
        )

    def stitch(
        self,
        instances: Sequence[LocalInstance],
        *,
        source_transform: SourceTransform,
    ) -> list[CellInstance]:
        if not instances:
            return []
        for instance in instances:
            if instance.calibrated_probabilities is None:
                raise ValueError("Instances must be calibrated before stitching")
        groups = _DisjointSet(len(instances))
        for left_index, left in enumerate(instances):
            for right_index in range(left_index + 1, len(instances)):
                if self._duplicates(left, instances[right_index]):
                    groups.union(left_index, right_index)
        grouped: dict[int, list[LocalInstance]] = {}
        for index, instance in enumerate(instances):
            grouped.setdefault(groups.find(index), []).append(instance)
        cells = [
            self._merge_group(group, source_transform=source_transform)
            for group in grouped.values()
        ]
        return sorted(cells, key=lambda cell: (cell.centroid_y_px, cell.centroid_x_px))

    def _merge_group(
        self,
        group: Sequence[LocalInstance],
        *,
        source_transform: SourceTransform,
    ) -> CellInstance:
        weights = np.asarray([instance.area_px for instance in group], dtype=np.float64)
        weights /= weights.sum()
        centroids = np.asarray([instance.global_centroid for instance in group])
        merged_x, merged_y = np.sum(centroids * weights[:, None], axis=0)
        probability_vectors = np.stack(
            [instance.calibrated_probabilities for instance in group], axis=0
        )
        probabilities = np.sum(probability_vectors * weights[:, None], axis=0)
        probabilities /= probabilities.sum()
        class_id, class_name, confidence, entropy, margin, acceptance = (
            self.calibrator.assess_probability_vector(probabilities)
        )
        x1 = min(instance.global_bbox[0] for instance in group)
        y1 = min(instance.global_bbox[1] for instance in group)
        x2 = max(instance.global_bbox[2] for instance in group)
        y2 = max(instance.global_bbox[3] for instance in group)
        source_x, source_y = source_transform.resampled_to_source(merged_x, merged_y)
        source_x1, source_y1 = source_transform.resampled_to_source(x1, y1)
        source_x2, source_y2 = source_transform.resampled_to_source(x2, y2)
        unique_pixels: set[tuple[int, int]] = set()
        for instance in group:
            unique_pixels.update(instance.global_pixels())
        source_area = len(unique_pixels) / (
            source_transform.scale_x * source_transform.scale_y
        )
        physical_x, physical_y = source_transform.source_to_physical(source_x, source_y)
        physical_area = None
        if (
            source_transform.trusted
            and source_transform.source_mpp_x is not None
            and source_transform.source_mpp_y is not None
        ):
            physical_area = (
                source_area
                * source_transform.source_mpp_x
                * source_transform.source_mpp_y
            )
        tile_ids = sorted({instance.tile_id for instance in group})
        stable_key = "|".join(sorted(instance.local_instance_id for instance in group))
        segmentation_confidence = float(
            np.sum(
                np.asarray([instance.segmentation_confidence for instance in group])
                * weights
            )
        )
        return CellInstance(
            instance_id=str(uuid5(NAMESPACE_URL, f"tme-nuclei-v2:{stable_key}")),
            class_id=class_id,
            class_name=class_name,
            centroid_x_px=float(source_x),
            centroid_y_px=float(source_y),
            centroid_x_um=physical_x,
            centroid_y_um=physical_y,
            area_px=float(source_area),
            area_um2=physical_area,
            bbox_xyxy=(source_x1, source_y1, source_x2, source_y2),
            class_probabilities=tuple(float(value) for value in probabilities),
            class_confidence=confidence,
            normalized_entropy=entropy,
            top1_top2_margin=margin,
            segmentation_confidence=segmentation_confidence,
            acceptance_status=acceptance,
            source_tile_ids=tile_ids,
        )
