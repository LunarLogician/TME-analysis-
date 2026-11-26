# WP-09 completion

## Files changed

- `Backend/app/ml/stitching.py`
- Stitching tests.

## Behavior changed

- Local instances become global cells through class-independent mask/centroid matching, union grouping, probability/geometry merging, deterministic IDs, and source/physical transforms.

## Tests run

- Cross-tile duplicate, nearby distinct nuclei, source/physical coordinate conversion.

## Acceptance criteria status

- Pass for deterministic synthetic cases.

## Remaining risks

- Grid-perturbation validation on notebook fixtures is pending.

## Intentional deviations

- None.
