# WP-12 completion

## Files changed

- `Backend/app/services/spatial_engine.py`
- Spatial tests.

## Behavior changed

- One engine uses only accepted cells in physical coordinates for counts, densities, ratios, bidirectional nearest-neighbor metrics, and optional tumor area.

## Tests run

- Accepted-vs-uncertain filtering, distances, and area/density calculations.

## Acceptance criteria status

- Minimum required metrics: pass.
- Boundary infiltration extensions: fields exist but require a tumor-boundary policy/validation dataset.

## Remaining risks

- Intratumoral/peritumoral band width is intentionally not invented without a versioned spatial policy.

## Intentional deviations

- Optional boundary metrics remain null until clinically versioned.
