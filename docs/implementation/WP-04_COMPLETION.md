# WP-04 completion

## Files changed

- `Backend/app/services/quality_service.py`
- `Backend/app/ml/preprocessing.py`
- V2 QC/scale tests.

## Behavior changed

- Added decode/channel/dimension/tissue/background/blur/exposure/scale QC, deterministic H&E compatibility screening, explicit scale priority, and physical resampling with round-trippable transforms.
- Non-H&E uploads are rejected before asset persistence, run creation, queueing, or model inference; execution-time QC repeats the gate for defense in depth.

## Tests run

- Unknown-scale, H&E/non-H&E, priority, resampling, transform, and end-to-end preflight rejection tests.

## Acceptance criteria status

- PASS/WARNING/FAIL and no trusted MPP fallback: pass.

## Remaining risks

- Scanner-specific metadata parsers should be extended as deployment scanners are known.
- The stain gate establishes H&E compatibility, not biopsy provenance; thresholds require local validation across scanners and stain variation.

## Intentional deviations

- Magnification-to-MPP has no implicit default mapping; it activates only when a validated mapping is injected.
