# WP-08 completion

## Files changed

- `Backend/app/ml/calibration.py`
- Calibration tests.

## Behavior changed

- Temperature plus class bias is applied after fusion; confidence, normalized entropy, margin, and bundle thresholds create ACCEPTED/UNCERTAIN review states.

## Tests run

- Accepted neoplastic and ambiguous abstention cases.

## Acceptance criteria status

- Pass.

## Remaining risks

- Notebook fixture parity remains required.

## Intentional deviations

- REJECTED is reserved for upstream invalid/tiny objects; calibrated valid nuclei are accepted or uncertain.
