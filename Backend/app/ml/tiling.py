"""Deterministic overlapping 256x256 tiling over tissue-bearing regions."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Tile:
    tile_id: str
    image: np.ndarray
    origin_x: int
    origin_y: int
    valid_width: int
    valid_height: int
    tissue_fraction: float


class TileGenerator:
    def __init__(
        self,
        tile_size: tuple[int, int],
        *,
        overlap: int = 64,
        minimum_tissue_fraction: float = 0.05,
        padding_value: int = 255,
    ):
        self.tile_height, self.tile_width = map(int, tile_size)
        self.overlap = int(overlap)
        self.minimum_tissue_fraction = float(minimum_tissue_fraction)
        self.padding_value = int(padding_value)
        if self.tile_height <= 0 or self.tile_width <= 0:
            raise ValueError("tile dimensions must be positive")
        if self.overlap < 0 or self.overlap >= min(self.tile_height, self.tile_width):
            raise ValueError("overlap must be non-negative and smaller than a tile")
        if not 0 <= self.minimum_tissue_fraction <= 1:
            raise ValueError("minimum_tissue_fraction must be in [0,1]")

    @staticmethod
    def _origins(length: int, tile_length: int, stride: int) -> list[int]:
        if length <= tile_length:
            return [0]
        origins = list(range(0, length - tile_length + 1, stride))
        final = length - tile_length
        if origins[-1] != final:
            origins.append(final)
        return origins

    def generate(self, image: np.ndarray, tissue_mask: np.ndarray) -> list[Tile]:
        if image.ndim != 3 or image.shape[2] != 3:
            raise ValueError("tiler requires RGB HxWx3 input")
        if tissue_mask.shape != image.shape[:2]:
            raise ValueError("tissue mask shape must match the image")
        stride_y = self.tile_height - self.overlap
        stride_x = self.tile_width - self.overlap
        y_origins = self._origins(image.shape[0], self.tile_height, stride_y)
        x_origins = self._origins(image.shape[1], self.tile_width, stride_x)
        tiles: list[Tile] = []
        for origin_y in y_origins:
            for origin_x in x_origins:
                valid_height = min(self.tile_height, image.shape[0] - origin_y)
                valid_width = min(self.tile_width, image.shape[1] - origin_x)
                local_mask = tissue_mask[
                    origin_y : origin_y + valid_height,
                    origin_x : origin_x + valid_width,
                ]
                tissue_fraction = float(np.count_nonzero(local_mask) / local_mask.size)
                if tissue_fraction < self.minimum_tissue_fraction:
                    continue
                tile_image = np.full(
                    (self.tile_height, self.tile_width, 3),
                    self.padding_value,
                    dtype=image.dtype,
                )
                tile_image[:valid_height, :valid_width] = image[
                    origin_y : origin_y + valid_height,
                    origin_x : origin_x + valid_width,
                ]
                tiles.append(
                    Tile(
                        tile_id=f"tile-{origin_y}-{origin_x}",
                        image=tile_image,
                        origin_x=origin_x,
                        origin_y=origin_y,
                        valid_width=valid_width,
                        valid_height=valid_height,
                        tissue_fraction=tissue_fraction,
                    )
                )
        return tiles
