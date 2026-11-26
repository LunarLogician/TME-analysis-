# WP-02 completion

## Files changed

- `Backend/app/ml/model_manager.py`
- `Backend/app/model_weights/tme_nuclei_v2/*`
- `Backend/tests/v2/test_bundle_and_preprocessing.py`

## Behavior changed

- V2 loads both TorchScript modules once, verifies a complete checksum inventory, parses all runtime JSON, validates class/config contracts, and dry-runs seven dense outputs plus the 132→5 classifier.

## Tests run

- Fresh CPU loads, exact output shapes, finite tensors, and corruption failure.

## Acceptance criteria status

- Local immutable bundle and fail-fast ModelManager: pass on CPU.
- GPU load: not run on this CPU environment.

## Remaining risks

- Obtain the publisher's original `.pt` archives to restore publisher-level byte hashes.

## Intentional deviations

- The supplied `.pt` files arrived expanded as directories. They were reassembled without changing TorchScript contents. The deployed checksum inventory records the resulting archive bytes; the six release JSON/report hashes remain identical to the supplied release.
