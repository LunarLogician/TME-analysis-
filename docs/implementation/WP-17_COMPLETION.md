# WP-17 completion

## Files changed

- `Backend/app/services/report_service.py`
- V2 protected report endpoints.

## Behavior changed

- Reports render nine deterministic sections from structured V2 results. They do not use model wording to establish tumor, change counts/state, diagnose, or predict treatment response.

## Tests run

- End-to-end PDF generation and PDF signature/size checks.

## Acceptance criteria status

- Deterministic report architecture: pass.

## Remaining risks

- Clinical layout/content review is required before release.

## Intentional deviations

- Gemini wording is disabled in the V2 report path until constrained-output review is added.
