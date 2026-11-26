# WP-20 completion

## Files changed

- `Backend/main.py`, V2 router registration, environment defaults.

## Behavior changed

- V2 is the default active startup/inference path; V1 runtime is opt-in with `ENABLE_LEGACY_V1_RUNTIME=true`. V2 does not resize the whole field, use Macenko, Hugging Face, or coerce TME states.

## Tests run

- V2 CPU and application tests.

## Acceptance criteria status

- Default-path cutover: pass.
- Physical deletion/archive of legacy code and weights: intentionally pending WP-10/GPU/staging gates.

## Remaining risks

- Do not delete V1 or rewrite historical rows until every release gate is complete.

## Intentional deviations

- Legacy routes/code remain for reproducibility, but are not loaded by default.
