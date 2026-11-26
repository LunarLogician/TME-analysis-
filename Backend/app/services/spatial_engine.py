"""Single physical-coordinate spatial measurement engine for V2 cells."""

from __future__ import annotations

from typing import Iterable, Optional, Sequence

import numpy as np
from scipy.spatial import KDTree

from app.domain.cells import AcceptanceStatus, BIOLOGICAL_CLASS_ORDER, CellInstance
from app.domain.image_metadata import ImageMetadata
from app.domain.spatial import SpatialMeasurements
from app.domain.tumor import TumorAssessment, TumorRegionMode, TumorStatus


class SpatialEngine:
    measurement_version = "spatial-v2.0"

    def measure(
        self,
        *,
        cells: Sequence[CellInstance],
        tumor: TumorAssessment,
        metadata: ImageMetadata,
        tissue_area_px: int,
        tumor_polygon_px: Optional[Sequence[tuple[float, float]]] = None,
    ) -> SpatialMeasurements:
        if not metadata.scale_trusted:
            raise ValueError("PHYSICAL_SCALE_UNKNOWN")
        if tumor.status != TumorStatus.PRESENT.value:
            raise ValueError("TUMOR_NOT_PRESENT")
        accepted = [
            cell
            for cell in cells
            if cell.acceptance_status == AcceptanceStatus.ACCEPTED.value
        ]
        uncertain = [
            cell
            for cell in cells
            if cell.acceptance_status == AcceptanceStatus.UNCERTAIN.value
        ]
        accepted_counts = {
            name: sum(cell.class_name == name for cell in accepted)
            for name in BIOLOGICAL_CLASS_ORDER
        }
        uncertain_counts = {
            name: sum(cell.class_name == name for cell in uncertain)
            for name in BIOLOGICAL_CLASS_ORDER
        }
        neo = [cell for cell in accepted if cell.class_name == "NEOPLASTIC"]
        immune = [cell for cell in accepted if cell.class_name == "INFLAMMATORY"]
        pixel_area_um2 = float(metadata.source_mpp_x * metadata.source_mpp_y)
        tissue_area_mm2 = tissue_area_px * pixel_area_um2 / 1_000_000.0
        tumor_area_mm2: Optional[float]
        if tumor.tumor_region_mode == TumorRegionMode.WHOLE_ROI.value:
            tumor_area_mm2 = tissue_area_mm2
        elif tumor_polygon_px:
            x = np.asarray([point[0] for point in tumor_polygon_px], dtype=np.float64)
            y = np.asarray([point[1] for point in tumor_polygon_px], dtype=np.float64)
            polygon_area_px = 0.5 * abs(
                float(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))
            )
            tumor_area_mm2 = polygon_area_px * pixel_area_um2 / 1_000_000.0
        else:
            tumor_area_mm2 = None

        warnings: list[str] = []
        neo_to_immune = self._nearest_distances(neo, immune)
        immune_to_neo = self._nearest_distances(immune, neo)
        if not neo:
            warnings.append("NO_ACCEPTED_NEOPLASTIC_CELLS")
        if not immune:
            warnings.append("NO_ACCEPTED_INFLAMMATORY_CELLS")
        return SpatialMeasurements(
            measurement_version=self.measurement_version,
            neo_count_accepted=len(neo),
            immune_count_accepted=len(immune),
            class_counts_accepted=accepted_counts,
            class_counts_uncertain=uncertain_counts,
            tissue_area_mm2=tissue_area_mm2,
            tumor_area_mm2=tumor_area_mm2,
            neo_density_mm2=len(neo) / tissue_area_mm2 if tissue_area_mm2 > 0 else None,
            immune_density_mm2=len(immune) / tissue_area_mm2 if tissue_area_mm2 > 0 else None,
            immune_to_neo_ratio=len(immune) / len(neo) if neo else None,
            neo_to_immune_mean_um=self._stat(neo_to_immune, np.mean),
            neo_to_immune_median_um=self._stat(neo_to_immune, np.median),
            neo_to_immune_p25_um=self._percentile(neo_to_immune, 25),
            neo_to_immune_p75_um=self._percentile(neo_to_immune, 75),
            immune_to_neo_mean_um=self._stat(immune_to_neo, np.mean),
            immune_to_neo_median_um=self._stat(immune_to_neo, np.median),
            measurement_warnings=warnings,
        )

    @staticmethod
    def _nearest_distances(
        sources: Sequence[CellInstance], targets: Sequence[CellInstance]
    ) -> np.ndarray:
        if not sources or not targets:
            return np.asarray([], dtype=np.float64)
        source_coordinates = np.asarray(
            [(cell.centroid_x_um, cell.centroid_y_um) for cell in sources],
            dtype=np.float64,
        )
        target_coordinates = np.asarray(
            [(cell.centroid_x_um, cell.centroid_y_um) for cell in targets],
            dtype=np.float64,
        )
        if not np.isfinite(source_coordinates).all() or not np.isfinite(target_coordinates).all():
            raise ValueError("Physical cell coordinates are missing or invalid")
        distances, _ = KDTree(target_coordinates).query(source_coordinates, k=1)
        return np.asarray(distances, dtype=np.float64)

    @staticmethod
    def _stat(values: np.ndarray, function) -> Optional[float]:
        return float(function(values)) if values.size else None

    @staticmethod
    def _percentile(values: np.ndarray, percentile: int) -> Optional[float]:
        return float(np.percentile(values, percentile)) if values.size else None
