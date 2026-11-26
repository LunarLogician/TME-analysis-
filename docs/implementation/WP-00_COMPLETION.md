# WP-00 completion

## Files changed

- Added this baseline record and the V2 regression suite under `Backend/tests/v2/`.

## Behavior changed

- None; this package records the pre-cutover behavior.

## Existing behavior recorded

- Startup loaded Hugging Face Mask2Former by default from `mask2former_pannuke.pth`.
- Uploaded fields were resized wholesale to 256×256 before inference.
- Missing/invalid MPP silently became trusted 0.25 µm/px.
- Scale normalization cropped/padded back to one 256×256 field.
- Macenko was environment-controlled but a normalizer was always constructed at startup.
- Legacy classes were zero-based in model adapters: neoplastic, inflammatory, connective, dead, epithelial.
- Confidence came from Mask2Former query/mask scores without V2 calibration or abstention.
- Spatial logic used nearest neoplastic→inflammatory centroid distance and historical 20/60 µm thresholds.
- `INDETERMINATE` was coerced to `Excluded` for the old database constraint.
- Heavy inference/report tasks used FastAPI `BackgroundTasks`.
- Legacy reports could ask Gemini for treatment-response and treatment recommendations.

## Tests run

- The legacy suite was started before implementation but its real-model test did not complete in a reasonable baseline window and was interrupted.
- Existing legacy test files remain present and unchanged by the isolated V2 modules.

## Acceptance criteria status

- Baseline behavior: documented.
- Legacy code preservation: pass; V1 remains opt-in pending V2 parity/cutover gates.

## Remaining risks

- The entire historical real-model suite still needs a long-running CI job.

## Intentional deviations

- None.
