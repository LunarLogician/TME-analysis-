"""Deterministic V2 overlays and machine-readable analysis artifacts."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Sequence

import cv2
import numpy as np

from app.domain.cells import AcceptanceStatus, CellInstance


CLASS_COLORS = {
    "NEOPLASTIC": (255, 92, 92),
    "INFLAMMATORY": (80, 160, 255),
    "CONNECTIVE": (80, 220, 165),
    "DEAD": (160, 160, 160),
    "EPITHELIAL": (172, 130, 255),
    "UNCERTAIN": (255, 205, 80),
}


class ArtifactService:
    def __init__(self, storage_root: str | Path):
        self.storage_root = Path(storage_root)

    def render_and_store(
        self,
        *,
        analysis_run_id: str,
        source_rgb: np.ndarray,
        cells: Sequence[CellInstance],
        tissue_mask: np.ndarray,
        diagnostics: dict,
    ) -> dict[str, dict]:
        destination = self.storage_root / "analysis-artifacts" / analysis_run_id
        destination.mkdir(parents=True, exist_ok=True)
        overlay = source_rgb.copy()
        for cell in cells:
            color_key = (
                "UNCERTAIN"
                if cell.acceptance_status == AcceptanceStatus.UNCERTAIN.value
                else cell.class_name
            )
            color = CLASS_COLORS[color_key]
            cv2.circle(
                overlay,
                (int(round(cell.centroid_x_px)), int(round(cell.centroid_y_px))),
                3,
                color,
                1,
                lineType=cv2.LINE_AA,
            )
        overlay_path = destination / "overlay.png"
        cv2.imwrite(str(overlay_path), cv2.cvtColor(overlay, cv2.COLOR_RGB2BGR))
        tissue_mask_path = destination / "tissue_mask.png"
        cv2.imwrite(str(tissue_mask_path), tissue_mask.astype(np.uint8) * 255)

        geojson_path = destination / "cells.geojson"
        features = []
        for cell in cells:
            features.append(
                {
                    "type": "Feature",
                    "id": cell.instance_id,
                    "geometry": {
                        "type": "Point",
                        "coordinates": [cell.centroid_x_px, cell.centroid_y_px],
                    },
                    "properties": cell.model_dump(mode="json"),
                }
            )
        geojson_path.write_text(
            json.dumps({"type": "FeatureCollection", "features": features}),
            encoding="utf-8",
        )
        diagnostics_path = destination / "diagnostics.json"
        diagnostics_path.write_text(
            json.dumps(diagnostics, indent=2, sort_keys=True), encoding="utf-8"
        )
        return {
            "overlay": {"path": str(overlay_path), "media_type": "image/png"},
            "tissue_mask": {"path": str(tissue_mask_path), "media_type": "image/png"},
            "cells_geojson": {
                "path": str(geojson_path),
                "media_type": "application/geo+json",
            },
            "diagnostics": {
                "path": str(diagnostics_path),
                "media_type": "application/json",
            },
        }

    def store_tumor_region(
        self,
        *,
        analysis_run_id: str,
        polygon_px: Sequence[tuple[float, float]],
    ) -> Path:
        if len(polygon_px) < 3:
            raise ValueError("A tumor-region polygon requires at least three points")
        destination = self.storage_root / "analysis-artifacts" / analysis_run_id
        destination.mkdir(parents=True, exist_ok=True)
        path = destination / "tumor_region.geojson"
        coordinates = [[float(x), float(y)] for x, y in polygon_px]
        coordinates.append(coordinates[0])
        path.write_text(
            json.dumps(
                {
                    "type": "FeatureCollection",
                    "features": [
                        {
                            "type": "Feature",
                            "geometry": {
                                "type": "Polygon",
                                "coordinates": [coordinates],
                            },
                            "properties": {"source": "CLINICIAN_ANNOTATION"},
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return path
