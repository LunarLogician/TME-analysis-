# TME-Insight V2 — MASTER Codex Implementation Specification
## Final localized TME-Nuclei V2 integration + pathologist-assisted TME workflow

> **Status:** FINAL implementation specification for the currently trained and localized `tme_nuclei_v2` model.
>
> **Audience:** Codex / senior developer implementing the TME-Insight V2 application.
>
> **Repository:** `TME-Insight`
>
> **Primary stack:** Flutter frontend + FastAPI backend + Supabase/PostgreSQL + object storage + PyTorch/TorchScript inference.
>
> **Goal:** Replace the legacy Mask2Former path with the finalized TME-Nuclei V2 deployment bundle and turn TME-Insight into a pathologist-assisted H&E nuclei/TME analysis system.
>
> **Important:** This is no longer a model-training plan. The V2 model has finished training and has been exported. The work below is application integration, inference parity, spatial analysis, persistence, UI, reporting, reliability, and validation.

---

# 0. Non-negotiable operating contract for Codex

Before editing any repository file:

1. Inspect the current file.
2. Search all callers/importers.
3. Identify tests and API/database compatibility.
4. Record the existing behavior.
5. Make the smallest coherent change.
6. Add/update tests in the same work package.
7. Do not delete legacy code before the V2 replacement has parity and cutover tests.
8. Do not silently change scientific semantics.
9. Do not hard-code values that already exist in the model bundle.
10. If repository reality differs from this specification, preserve the scientific/inference requirements and adapt file locations to the actual codebase.

For every work package, create a short completion note under:

```text
docs/implementation/WP-XX_COMPLETION.md
```

containing:

```text
files changed
behavior changed
tests run
acceptance criteria status
remaining risks
intentional deviations
```

---

# 1. Final V2 model bundle — source of truth

Deploy the entire model release together:

```text
Backend/app/model_weights/tme_nuclei_v2/
    model.pt
    instance_classifier.pt
    model_manifest.json
    postprocess.json
    calibration.json
    class_map.json
    model_release_report.json
    model_release_report.md
    CHECKSUMS.sha256
```

Never mix files from different releases.

The application must treat:

```text
model_manifest.json
postprocess.json
calibration.json
class_map.json
CHECKSUMS.sha256
```

as runtime configuration/provenance, not documentation only.

## 1.1 Current finalized bundle identity

Expected current release:

```text
model_name:       tme_nuclei_v2
model_version:    2.0.0
framework:        PyTorch/TorchScript
training_dataset: PanNuke
outer_test_fold:  3
patch_size:       256×256
expected_mpp:     0.25 µm/px
expected_mag:     40×
```

Do not hard-code those values in application logic. Read them from the manifest and validate them.

## 1.2 Biological class order

Binding order:

```text
1 NEOPLASTIC
2 INFLAMMATORY
3 CONNECTIVE
4 DEAD
5 EPITHELIAL
```

`UNCERTAIN` is not a sixth biological class.

Application states:

```text
ACCEPTED
UNCERTAIN
REJECTED
```

must be stored separately from the biological class.

---

# 2. Exact model I/O contract

## 2.1 Dense model

Load with:

```python
torch.jit.load(...)
```

Do not reconstruct the training architecture.

Input:

```text
[B, 3, 256, 256]
```

Output tuple:

```text
0  np_logits        [B, 2, 256, 256]
1  hv_map           [B, 2, 256, 256]
2  nt_logits        [B, 5, 256, 256]
3  contour_logits   [B, 1, 256, 256]
4  seed_logits      [B, 1, 256, 256]
5  feature_map      [B, 32, 256, 256]
6  global_context   [B, 64]
```

All seven outputs are required for this release.

## 2.2 Instance classifier

Load:

```text
instance_classifier.pt
```

Input descriptor:

```text
132 dimensions
```

constructed exactly as:

```text
32 interior feature values
32 surrounding-ring feature values
64 global patch-context values
4 shape values
```

Shape values:

```text
normalized_area
normalized_bbox_height
normalized_bbox_width
area_to_box_occupancy
```

Output:

```text
[B_instances, 5]
```

five-class instance logits.

## 2.3 No Internet dependency

The V2 production path must not need:

```text
Hugging Face
Mask2Former
torchvision pretrained downloads
PanNuke training data
Internet access
training checkpoints
optimizer state
```

TorchScript deployment artifacts are sufficient.

---

# 3. Exact preprocessing contract

The legacy application behavior:

```text
whole uploaded image
→ resize to 256×256
→ model
```

must be removed from the V2 path.

Correct V2 path:

```text
original H&E image
    ↓
persist unchanged
    ↓
read metadata / MPP / magnification
    ↓
image QC
    ↓
if scale trusted: physically resample to manifest expected MPP
    ↓
tissue/background mask
    ↓
overlapping 256×256 tiles
    ↓
RGB float [0,1]
    ↓
ImageNet normalization from manifest
    ↓
model.pt
```

## 3.1 Exact normalization

Read from the manifest.

Current release values are approximately:

```text
mean = [0.485, 0.456, 0.406]
std  = [0.229, 0.224, 0.225]
```

The backend must not duplicate these as independent constants.

## 3.2 Stain handling

Current manifest:

```text
stain_normalization.required = false
```

Therefore:

- do not enable Macenko only in production;
- do not normalize the image differently from the notebook;
- stain augmentation used during training is not a deployment preprocessing step.

## 3.3 Test-time augmentation

The current localized release should default to **no TTA**.

Do not add flip TTA unless a future bundle explicitly declares and validates it.

---

# 4. Physical scale / MPP policy

Priority:

```text
1. reliable WSI metadata
2. reliable TIFF/scanner metadata
3. explicit user-provided MPP
4. validated magnification-to-MPP policy
5. UNKNOWN
```

Never silently treat a fallback constant as trusted physical scale.

If MPP is unknown:

```text
nuclei inference                 allowed
pixel centroids                  allowed
cell counts                      allowed
physical micron coordinates      null
distance in µm                   unavailable
density/mm²                      unavailable
physical TME phenotype           NOT_ASSESSABLE
reason                           PHYSICAL_SCALE_UNKNOWN
```

When source MPP is known:

```text
scale_x = source_mpp_x / target_mpp_x
scale_y = source_mpp_y / target_mpp_y
```

Preserve transforms for:

```text
tile/model pixels
resampled image pixels
original source pixels
physical micrometres
```

---

# 5. Exact V2 post-processing

`postprocess.json` is the source of truth.

Current release values:

```text
np_threshold         = 0.45
seed_threshold       = 0.60
min_nucleus_size     = 10
marker_min_size      = 4
hv_boundary_weight   = 0.60
contour_weight       = 0.40
morphology_open      = false
morphology_kernel    = 3
instance_head_blend  = 0.70
```

Do not hard-code them in inference code.

Required instance reconstruction:

```text
NP logits
→ softmax foreground probability
→ threshold
→ configured morphology
→ learned seed probability
→ seed threshold
→ remove small markers
→ conservative marker fallback only when seed markers fail
→ HV boundary energy
→ contour probability
→ configured HV + contour boundary weighting
→ marker-controlled watershed
→ remove tiny objects
→ contiguous relabel
→ geometry
```

The application implementation must match notebook behavior closely enough to pass deterministic parity tests.

---

# 6. Exact instance classification and fusion

For each reconstructed nucleus:

1. Pool 32-channel feature map over nucleus interior.
2. Pool same 32 channels over a surrounding ring.
3. Attach the 64-D global context vector from the same source patch.
4. Compute the four exact shape features.
5. Build one 132-D descriptor.
6. Run `instance_classifier.pt`.
7. Pool five-class NT pixel probabilities inside the nucleus.
8. Fuse the two probability vectors.

Conceptually:

```text
P_instance = softmax(instance_classifier(descriptor))
P_pixel    = mean(softmax(NT logits) inside nucleus)

P_fused =
    blend * P_instance
    + (1 - blend) * P_pixel

P_fused = P_fused / sum(P_fused)
```

`blend` comes from `postprocess.json`.

Do not reapply train-time logit adjustment.

---

# 7. Exact calibration + uncertainty

Current bundle uses:

```text
method = temperature_plus_class_bias
```

Calibration must be applied after the fused probability vector is constructed.

Conceptually:

```text
log_p = log(clip(P_fused, 1e-8, 1.0))
z = (log_p + class_bias) / temperature
P_calibrated = softmax(z)
```

Read exact temperature and bias from `calibration.json`.

Then calculate:

```text
predicted_class
confidence
normalized_entropy
top1_top2_margin
```

Apply bundle acceptance policy.

Current release includes approximately:

```text
Neoplastic minimum confidence = 0.95
Other classes minimum confidence = 0.55
Maximum normalized entropy = 0.85
Minimum top1-top2 margin = 0.05
```

Again: read these from the bundle.

Only accepted biological identities are used by default for tumor-dependent spatial measurements.

Uncertain cells must remain available in:

```text
overlay
cell table
counts
review UI
```

---

# 8. Canonical domain vocabulary

## 8.1 TME states

```text
HOT
COLD
EXCLUDED
INDETERMINATE
NOT_ASSESSABLE
NOT_APPLICABLE
```

Rules:

- `NOT_APPLICABLE`: no tumor is established/confirmed.
- `NOT_ASSESSABLE`: technical limitation such as unknown scale or failed QC.
- `INDETERMINATE`: tumor exists, but biological/spatial evidence is insufficient.
- `HOT/COLD/EXCLUDED`: only after valid tumor context + valid scale + sufficient spatial evidence.

Never silently coerce:

```text
INDETERMINATE → EXCLUDED
NOT_APPLICABLE → COLD
NOT_ASSESSABLE → EXCLUDED
```

---

# 9. Pathologist-assisted tumor-context workflow

This V2 application must not wait for an autonomous breast tumor model.

Support:

```text
CLINICIAN_CONFIRMED_TUMOR
CLINICIAN_CONFIRMED_NO_TUMOR
UNCONFIRMED_NUCLEI_ONLY
VALIDATED_AI_TUMOR_GATE   # reserved for future
```

## 9.1 Clinician-confirmed tumor

Pathologist confirms the ROI is tumor-containing or provides a tumor region.

Then:

```text
V2 cell analysis
→ accepted global cells
→ spatial engine
→ versioned TME policy
→ structured report
```

## 9.2 Clinician-confirmed no tumor

Return:

```text
tumor_status = ABSENT
TME = NOT_APPLICABLE
```

Nuclei counts/overlays may still be displayed.

## 9.3 Unconfirmed nuclei-only

Allow:

```text
nucleus segmentation
nucleus classification
counts
uncertainty
overlay
```

but do not promote predicted neoplastic cells to confirmed tumor.

TME remains unavailable until tumor context is confirmed or a future validated gate is added.

## 9.4 Tumor region modes

Support:

```text
WHOLE_ROI
ANNOTATED_REGION
NONE
```

Store who confirmed tumor context and when.

---

# 10. Canonical backend domain objects

Use Pydantic/dataclasses consistent with repository conventions.

## `ImageMetadata`

```text
asset_id
original_filename
mime_type
width_px
height_px
channels
bit_depth optional
scanner optional
source_mpp_x optional
source_mpp_y optional
source_magnification optional
effective_mpp_x optional
effective_mpp_y optional
effective_magnification optional
scale_source
scale_trusted
checksum_sha256
```

## `QualityAssessment`

```text
status: PASS | WARNING | FAIL
blur_score optional
tissue_fraction
background_fraction
exposure_score optional
resolution_valid
scale_valid
warnings[]
failures[]
```

## `CellInstance`

```text
instance_id
class_id
class_name
centroid_x_px
centroid_y_px
centroid_x_um optional
centroid_y_um optional
area_px
area_um2 optional
bbox_xyxy
class_probabilities[5]
class_confidence
normalized_entropy
top1_top2_margin
segmentation_confidence optional
acceptance_status
source_tile_ids[]
tumor_membership optional
```

## `TumorAssessment`

```text
status:
    PRESENT
    ABSENT
    INDETERMINATE

evidence_source:
    CLINICIAN_CONFIRMED_TUMOR
    CLINICIAN_CONFIRMED_NO_TUMOR
    UNCONFIRMED_NUCLEI_ONLY
    VALIDATED_AI_TUMOR_GATE

confirmed_by_user_id optional
confirmed_at optional
tumor_region_mode optional
tumor_region_artifact_id optional
confident_neoplastic_count
uncertain_neoplastic_count
neoplastic_density_mm2 optional
spatial_coherence_score optional
reason_codes[]
```

## `SpatialMeasurements`

```text
neo_count_accepted
immune_count_accepted
tissue_area_mm2 optional
tumor_area_mm2 optional

neo_density_mm2 optional
immune_density_mm2 optional
immune_to_neo_ratio optional

neo_to_immune_mean_um optional
neo_to_immune_median_um optional
neo_to_immune_p25_um optional
neo_to_immune_p75_um optional

immune_to_neo_mean_um optional
immune_to_neo_median_um optional

intratumoral_immune_density_mm2 optional
peritumoral_immune_density_mm2 optional
boundary_infiltration_score optional

measurement_warnings[]
```

## `TMEAssessment`

```text
state
policy_version
score optional
reason_codes[]
input_measurement_version
```

## `AnalysisOutput`

```text
analysis_run_id
session_id
status
image_metadata
quality
model_metadata
cell_counts
accepted_cell_counts
uncertain_cell_counts
cells_summary
tumor_assessment
spatial_measurements optional
tme_assessment
warnings[]
artifacts
created_at
completed_at optional
```

---

# 11. Target backend service graph

```text
routers
  ↓
AnalysisService
  ↓
JobQueue
  ↓
AnalysisWorker
  ↓
ImageAssetService
  ↓
MetadataReader
  ↓
QualityController
  ↓
ScaleNormalizer
  ↓
TissueMasker
  ↓
TileGenerator
  ↓
ModelManager
  ↓
NucleiPredictor
  ↓
InstancePostprocessor
  ↓
ConfidenceCalibrator
  ↓
InstanceStitcher
  ↓
TumorContextService
  ↓
SpatialEngine
  ↓
TMEPolicy
  ↓
ResultRepository
  ↓
ArtifactRepository
```

Reporting:

```text
ResultRepository
  ↓
ClinicalAnalysisContextBuilder
  ↓
ReportService
  ├── deterministic structured findings
  └── optional Gemini wording layer
  ↓
PDF/report renderer
```

---

# 12. Recommended backend package layout

Adapt to repository conventions rather than moving files blindly.

```text
Backend/app/
    domain/
        analysis.py
        cells.py
        image_metadata.py
        quality.py
        tumor.py
        spatial.py
        tme.py
        model_metadata.py

    ml/
        model_manager.py
        predictor.py
        preprocessing.py
        tiling.py
        postprocessing.py
        calibration.py
        stitching.py
        adapters/
            legacy_mask2former.py
            tme_nuclei_v2.py

    services/
        analysis_service.py
        image_asset_service.py
        quality_service.py
        tumor_context_service.py
        spatial_engine.py
        tme_policy.py
        report_service.py

    workers/
        analysis_worker.py
        worker_app.py

    repositories/
        analysis_repository.py
        cell_repository.py
        artifact_repository.py
        model_repository.py

    routers/
        analysis_v2.py
        artifacts_v2.py
        reports.py
```

---

# 13. Work package order

Recommended implementation order now that training is finished:

```text
WP-00 baseline
WP-01 domain contracts
WP-02 localized model bundle + ModelManager
WP-03 source-image persistence
WP-04 image scale + QC
WP-05 V2 256×256 tiling
WP-06 dense TorchScript inference
WP-07 exact watershed + 132-D classifier
WP-08 calibration + abstention
WP-09 cross-tile stitching
WP-10 notebook/backend parity
WP-11 pathologist tumor-context workflow
WP-12 spatial engine
WP-13 TME policy
WP-14 DB migration
WP-15 API
WP-16 Flutter
WP-17 reporting
WP-18 durable worker
WP-19 validation/security/observability
WP-20 cutover and legacy retirement
```

---

# WP-00 — Baseline and safety net

## Goal

Capture current Mask2Former behavior before replacing it.

## Required

Document:

```text
backend startup
frontend startup
current model loader
current preprocessing
whole-field resizing
MPP fallback
Macenko behavior
class mapping
current confidence logic
spatial thresholds
TME DB constraints
BackgroundTasks usage
report-generation behavior
```

Repository search:

```text
Mask2Former
mask2former_pannuke.pth
256
0.25
HOT
COLD
EXCLUDED
INDETERMINATE
BackgroundTasks
spatial_metrics
segmentation_results
Gemini
```

Add at least one legacy end-to-end regression test.

## Done when

Old application still runs and every legacy behavior being intentionally changed is documented.

---

# WP-01 — Canonical V2 contracts

Implement the objects in Section 10.

Tests must enforce:

```text
five biological classes exactly
UNCERTAIN is not biological class
probability vector length = 5
physical coordinates null when scale untrusted
HOT/COLD/EXCLUDED require tumor PRESENT
NOT_APPLICABLE when no tumor context
NOT_ASSESSABLE carries technical reason
```

Do not import Mask2Former in domain contracts.

---

# WP-02 — Localized bundle + ModelManager

## Replace

```text
construct Mask2Former
load mask2former_pannuke.pth
```

with immutable bundle loading.

## Responsibilities

```text
resolve active model version
verify checksums
parse manifest
verify class order
load model.pt once
load instance_classifier.pt once
eval mode
configured CPU/GPU device
expose model metadata
expose preprocessing config
expose postprocess config
expose calibration config
predict_batch()
```

Startup must fail on:

```text
missing file
checksum mismatch
bad class order
wrong model version
wrong output count
wrong tensor shape
invalid config
```

No silent Mask2Former fallback.

---

# WP-03 — Original source persistence

Persist the exact image before inference.

Suggested storage:

```text
analysis-source/{patient_id}/{session_id}/source.<ext>
analysis-source/{patient_id}/{session_id}/metadata.json
analysis-source/{patient_id}/{session_id}/preview.jpg

analysis-artifacts/{analysis_run_id}/overlay.png
analysis-artifacts/{analysis_run_id}/cells.parquet
analysis-artifacts/{analysis_run_id}/cells.geojson
analysis-artifacts/{analysis_run_id}/tissue_mask.png
analysis-artifacts/{analysis_run_id}/tumor_region.geojson
analysis-artifacts/{analysis_run_id}/diagnostics.json
```

Rules:

```text
source image stays unchanged
preview is separate
preview never enters ML pipeline
SHA-256 source
preserve original dimensions
access-control all artifacts
```

---

# WP-04 — Quality + physical scale

Implement:

```text
decode success
dimensions
tissue fraction
background fraction
gross blur
gross exposure
scale validity
supported channels
```

Statuses:

```text
PASS
WARNING
FAIL
```

Scale trust must remain explicit.

A QC `FAIL` prevents ML inference unless an explicit development-only override is enabled.

---

# WP-05 — V2 overlapping tiler

Current V2 is a local single-scale patch model.

Required:

```text
tile size from manifest: 256×256
configurable overlap
deterministic padding
tissue-fraction skip
exact source transform
```

Do not implement mandatory external context/DINO input for V2.

Tiler interface may remain future-ready for V3.

---

# WP-06 — Dense V2 predictor

Create:

```text
NucleiPredictor.predict_batch()
```

Use:

```text
torch.inference_mode()
```

Validate seven outputs exactly.

Reject:

```text
NaN/Inf
wrong batch alignment
wrong NT channels
wrong spatial sizes
missing global context
```

Collect:

```text
inference_ms
batch_size
device
peak_vram optional
```

---

# WP-07 — V2 instance post-processing + classification

Reproduce Section 5 and Section 6 exactly.

Tests must include:

```text
isolated nucleus
two touching nuclei
three clustered nuclei
edge nucleus
small artifact
weak seed
multiple seeds
HV separation
contour separation
descriptor_dim == 132
classifier output == 5
```

No new hard-coded postprocessing constants.

---

# WP-08 — Calibration + acceptance

Implement exact bundle calibration.

Persist for each nucleus:

```text
five calibrated probabilities
predicted biological class
confidence
normalized entropy
top1-top2 margin
acceptance_status
```

Only accepted biological identities enter accepted spatial counts by default.

---

# WP-09 — Stitching and global coordinates

Local tile counts are not final counts.

Required flow:

```text
local instances
→ transform to global coordinates
→ overlap matching
→ duplicate reconciliation
→ global instance ID
→ recompute/merge probability and geometry
→ final cell table
```

Duplicate matching may use:

```text
mask IoU
centroid distance
border proximity
probability compatibility
```

Do not require exact class equality for duplicate matching.

Tests:

```text
same nucleus across tiles becomes one
nearby distinct nuclei remain two
grid-origin perturbation changes count minimally
coordinate round-trip is accurate
```

---

# WP-10 — Notebook-to-backend parity gate

This is mandatory before production cutover.

Prepare deterministic fixture tiles from the notebook or an exported fixture package.

For the same normalized input verify:

```text
dense output count exact
dense output shapes exact
all tensors finite
NP probability close
seed probability close
contour probability close
watershed instance count exact
instance geometry within tolerance
descriptor dimension exactly 132
descriptor values within tolerance
instance classifier probabilities within tolerance
pixel type probabilities within tolerance
fused probabilities within tolerance
calibrated probabilities within tolerance
acceptance decision exact
```

If parity fails, do not blame/retrain the model first. Fix localization.

---

# WP-11 — Pathologist tumor-context workflow

Implement:

```text
CLINICIAN_CONFIRMED_TUMOR
CLINICIAN_CONFIRMED_NO_TUMOR
UNCONFIRMED_NUCLEI_ONLY
VALIDATED_AI_TUMOR_GATE
```

Store:

```text
status
evidence_source
confirmed_by_user_id
confirmed_at
region_mode
region artifact
reason codes
```

Important:

Changing tumor context should not rerun the neural model.

Reuse stored cells:

```text
tumor context change
→ spatial engine
→ TME policy
→ report refresh
```

---

# WP-12 — One physical-coordinate SpatialEngine

Input:

```text
global CellInstance[]
TumorAssessment
TumorRegion optional
ImageMetadata
SpatialPolicy
```

Minimum metrics:

```text
accepted neoplastic count
accepted inflammatory count
counts for all five classes
accepted vs uncertain counts

tissue area
tumor area when region exists

neoplastic density/mm²
inflammatory density/mm²
immune:neoplastic ratio

neo→immune nearest neighbor:
mean
median
p25
p75

immune→neo:
mean
median

intratumoral immune density optional
peritumoral immune density optional
boundary infiltration optional
```

Preconditions for physical TME:

```text
quality != FAIL
scale_trusted == true
tumor == PRESENT
sufficient cell evidence
```

---

# WP-13 — Versioned TME policy

SpatialEngine returns measurements only.

Separate:

```text
TMEPolicy.evaluate(...)
```

Canonical outputs:

```text
HOT
COLD
EXCLUDED
INDETERMINATE
NOT_ASSESSABLE
NOT_APPLICABLE
```

The historical 20/60 µm logic may remain as:

```text
TMEPolicyV1
```

for backward/research comparison:

```text
HOT       <20 µm
EXCLUDED  20–60 µm
COLD      >60 µm
```

but it must not run when evidence is invalid/insufficient.

Do not classify a ROI from a trivial number of cells.

If tumor confirmed but immune evidence insufficient:

```text
INDETERMINATE
```

---

# WP-14 — Database migration

Preserve current tables during migration.

Recommended additions:

## `model_versions`

```text
id
model_name
version
architecture
checkpoint_sha256
manifest_json
calibration_version
postprocess_version
active
created_at
```

## `image_assets`

```text
id
session_id
storage_path
sha256
mime_type
width_px
height_px
mpp_x
mpp_y
magnification
scale_source
scale_trusted
created_at
```

## `analysis_runs`

```text
id
session_id
image_asset_id
model_version_id
status
stage
progress
quality_status
effective_mpp_x
effective_mpp_y
tile_count
processed_tile_count
accepted_cell_count
uncertain_cell_count
started_at
completed_at
failure_code
failure_message
config_snapshot
```

## `cell_instances`

```text
analysis_run_id
instance_id
class_name
class_id
centroid_x_px
centroid_y_px
centroid_x_um nullable
centroid_y_um nullable
area_px
area_um2 nullable
confidence
entropy
margin
acceptance_status
probabilities
bbox
source_tile_ids
tumor_membership
```

For very large cell tables, use Parquet/GeoJSON in object storage plus summary/index rows in PostgreSQL if measurements demonstrate that storing every cell row is too heavy.

## `tumor_assessments`

Include the human-confirmation provenance fields.

## `spatial_analysis_results`

Store raw metrics and measurement version.

## `tme_assessments`

Store canonical state and policy version.

## `analysis_artifacts`

Store overlay/cell-table/tumor-region/etc references.

Update TME constraints to accept all six canonical states.

RLS/ownership rules are mandatory.

---

# WP-15 — V2 API

Suggested endpoints:

```text
POST /v2/sessions/{session_id}/analysis
GET  /v2/analysis/{analysis_run_id}
GET  /v2/analysis/{analysis_run_id}/cells
GET  /v2/analysis/{analysis_run_id}/quality
GET  /v2/analysis/{analysis_run_id}/artifacts
GET  /v2/analysis/{analysis_run_id}/overlay
GET  /v2/analysis/{analysis_run_id}/tumor
GET  /v2/analysis/{analysis_run_id}/spatial
POST /v2/analysis/{analysis_run_id}/tumor-context
POST /v2/analysis/{analysis_run_id}/recompute-tme
```

Analysis start supports:

```text
source image
optional MPP
optional magnification
scanner metadata
analysis_mode
initial tumor evidence optional
tumor region optional
```

Modes:

```text
NUCLEI_ONLY
PATHOLOGIST_CONFIRMED_TME
NO_TUMOR
```

Stages:

```text
QUEUED
VALIDATING_IMAGE
READING_METADATA
RESAMPLING
TISSUE_MASKING
TILING
NUCLEAR_INFERENCE
INSTANCE_RECONSTRUCTION
CALIBRATION
STITCHING
PERSISTING_CELLS
AWAITING_TUMOR_CONTEXT optional
SPATIAL_ANALYSIS
TME_INTERPRETATION
RENDERING_ARTIFACTS
COMPLETE
FAILED
```

`/cells` must paginate/stream.

---

# WP-16 — Flutter V2 workflow

## Upload

Show scale as:

```text
Detected
User provided
Unknown
```

Preserve original source.

## Analysis progress

Show real stages:

```text
Validating image
Reading scale
Tiling
Analyzing nuclei 73/160
Reconstructing nuclei
Calibrating classifications
Stitching cells
Saving results
```

## Nuclei review screen

Display:

```text
total detected nuclei
accepted
uncertain
class counts
```

Overlay toggles:

```text
Neoplastic
Inflammatory
Connective
Dead
Epithelial
Uncertain
```

Click/tap nucleus:

```text
class
five probabilities
confidence
entropy
margin
acceptance
area
pixel coordinates
µm coordinates when valid
```

## Tumor context UI

After nuclei analysis:

```text
[ Confirm tumor in whole ROI ]
[ Draw/confirm tumor region ]
[ Confirm no tumor ]
[ Leave unconfirmed ]
```

## TME screen

Show all canonical states distinctly.

Do not show unavailable physical metrics when scale is unknown.

---

# WP-17 — Report architecture

Report facts come from structured results, not Gemini.

Suggested sections:

```text
1. Clinical information supplied by clinician
2. Image quality / scale
3. AI nuclei analysis
4. Accepted and uncertain cell counts
5. Tumor-context provenance
6. Spatial TME measurements
7. TME interpretation
8. Limitations / uncertainty
9. Model version / analysis provenance
```

Gemini may:

```text
summarize
improve readability
explain already-computed findings
```

Gemini may not:

```text
change cell counts
establish tumor presence
change TME state
invent diagnosis
invent history
invent treatment response
```

Allowed style:

```text
"Findings are consistent with the configured HOT TME policy."
"Inflammatory cells show close spatial proximity to accepted neoplastic cells."
"These findings may be relevant to immunotherapy-oriented pathological review."
```

Do not claim:

```text
"The patient will respond to pembrolizumab."
```

unless a separately trained outcome model exists in the future.

---

# WP-18 — Durable worker

Move heavy inference out of FastAPI `BackgroundTasks`.

Recommended architecture:

```text
FastAPI
→ Redis-backed queue
→ GPU/CPU analysis worker
```

Choose one queue framework already suitable for the repository:

```text
Celery
RQ
Dramatiq
```

not multiple.

Job payload should use IDs, not raw image bytes.

Model is loaded once per worker lifecycle.

Required:

```text
idempotency
retry only retryable failures
persist stage/progress
clean GPU memory on failure
worker restart safety
no duplicate cell rows
```

---

# WP-19 — Validation, security, observability

## 19.1 Localized nuclei-engine release gate

Required before default V2 cutover:

```text
bundle checksum PASS
CPU load PASS
GPU load PASS when GPU deployment used
seven outputs PASS
watershed parity PASS
132-D descriptor parity PASS
classifier parity PASS
fusion parity PASS
calibration parity PASS
abstention parity PASS
stitching tests PASS
source-coordinate tests PASS
```

## 19.2 Current bundle reference metrics

Current release report contains approximately:

```text
held-out Fold 3 images: 2722
mPQ:  0.5027
bPQ:  0.6503
DQ:   0.7906
SQ:   0.8225
Dice: 0.8351
AJI+: 0.6952
```

Per-class PQ approximately:

```text
Neoplastic    0.6000
Inflammatory  0.5723
Connective    0.4712
Dead          0.2658
Epithelial    0.6042
```

Calibration reference:

```text
ECE before: 0.0364
ECE after:  0.0196
held-out matched ECE: 0.0121
accepted coverage: ~71.7%
accepted accuracy: ~90.4%
```

These values are release provenance, not values to hard-code into application behavior.

## 19.3 Autonomous breast tumor-gate validation — later phase

Before a future AI is allowed to independently establish breast tumor presence, require external breast validation including:

```text
normal breast
adenosis
sclerosing adenosis
usual ductal hyperplasia
fibroadenoma
papilloma
radial scar
apocrine change
fibrosis
inflammatory tissue
malignant breast samples
scanner/stain diversity
```

Metrics:

```text
benign specificity
false neoplastic nuclei/mm²
false tumor-gate positive rate
tumor-region agreement
```

This does not block the pathologist-confirmed workflow.

## 19.4 Security

Production:

```text
JWT verification mandatory
no permissive auth fallback
CORS configured
signed URLs short-lived
patient ownership checked server-side
service-role secrets backend only
Gemini key backend only
no secrets in Flutter
```

## 19.5 Observability

Log:

```text
request_id
user_id
patient_id where authorized
session_id
analysis_run_id
model_version
model checksum
stage
tile count
processed tiles
cell count
uncertain fraction
duration
error_code
```

Do not log raw pathology bytes.

---

# WP-20 — Cutover and legacy retirement

Only after all V2 acceptance tests pass:

Remove/deprecate:

```text
whole-image resize to 256×256
default Mask2Former runtime
mask2former_pannuke.pth production dependency
duplicate pixel spatial route
legacy HOT/COLD pixel thresholds
silent INDETERMINATE→EXCLUDED conversion
heavy FastAPI BackgroundTasks
direct treatment-response claims
```

Archive old model for reproducibility if needed:

```text
Model/archive/mask2former_v1/
```

Do not rewrite historical analysis rows as V2 outputs unless images are deliberately re-analyzed.

Final target:

```text
one active V2 inference path
one global cell representation
one spatial engine
one TME policy interface
one canonical TME-state vocabulary
```

---

# 14. Canonical end-to-end pipeline

```python
def execute_analysis(analysis_run_id):
    run = repo.get_analysis_run(analysis_run_id)
    asset = asset_service.load(run.image_asset_id)

    repo.set_stage(run.id, "VALIDATING_IMAGE")

    image, metadata = metadata_reader.decode(asset)
    quality = quality_controller.assess(image, metadata)

    if quality.status == "FAIL":
        return finalize_not_assessable(
            run,
            reason="IMAGE_QUALITY_FAILED",
            quality=quality,
        )

    scale = scale_normalizer.resolve(
        metadata=metadata,
        user_override=run.user_scale_override,
    )

    if scale.is_trusted:
        model_image, source_transform = scale_normalizer.resample_to_model_scale(
            image=image,
            source_scale=scale,
            target_mpp=model_manager.expected_mpp,
        )
    else:
        model_image = image
        source_transform = pixel_only_transform()

    tissue_mask = tissue_masker.compute(model_image)

    tiles = tile_generator.generate(
        image=model_image,
        tissue_mask=tissue_mask,
        manifest=model_manager.manifest,
    )

    local_instances = []

    for tile_batch in batcher(tiles):
        dense = predictor.predict_batch(tile_batch)

        reconstructed = postprocessor.reconstruct(
            dense=dense,
            tiles=tile_batch,
            postprocess_config=model_manager.postprocess_config,
        )

        classified = instance_classifier.classify_and_fuse(
            reconstructed,
            dense,
            classifier=model_manager.instance_classifier,
            config=model_manager.postprocess_config,
        )

        calibrated = calibrator.apply(
            classified,
            config=model_manager.calibration_config,
        )

        local_instances.extend(calibrated)
        repo.update_tile_progress(...)

    cells = stitcher.stitch(
        local_instances,
        source_transform=source_transform,
        scale=scale,
    )

    repo.persist_cells(cells)

    tumor_context = tumor_context_service.resolve(run, cells)

    if not scale.is_trusted:
        spatial = None
        tme = TMEAssessment(
            state="NOT_ASSESSABLE",
            reason_codes=["PHYSICAL_SCALE_UNKNOWN"],
        )

    elif tumor_context.status != "PRESENT":
        spatial = None
        tme = TMEAssessment(
            state="NOT_APPLICABLE",
            reason_codes=["TUMOR_NOT_CONFIRMED"],
        )

    else:
        spatial = spatial_engine.measure(
            cells=cells,
            tumor=tumor_context,
            metadata=metadata,
        )

        tme = tme_policy.evaluate(
            spatial=spatial,
            tumor=tumor_context,
            quality=quality,
        )

    artifacts = artifact_service.render_and_store(
        source=image,
        cells=cells,
        tumor=tumor_context,
        tissue_mask=tissue_mask,
    )

    result = result_builder.build(
        run=run,
        image_metadata=metadata,
        quality=quality,
        cells=cells,
        tumor=tumor_context,
        spatial=spatial,
        tme=tme,
        artifacts=artifacts,
    )

    repo.persist_output(result)
    repo.mark_complete(run.id)

    return result
```

---

# 15. Required end-to-end acceptance scenarios

## Scenario A — Pathologist-confirmed tumor ROI + trusted MPP

Expected:

```text
source stored
scale trusted
correct resampling
overlapping tiles
V2 nuclei results
stitched global cells
clinician tumor context PRESENT
physical spatial metrics
TME state
overlay
report
```

## Scenario B — Clinician confirms no tumor

Expected:

```text
nuclei results allowed
tumor ABSENT
TME NOT_APPLICABLE
no tumor-dependent interpretation
```

## Scenario C — Nuclei-only unconfirmed case

Expected:

```text
cell segmentation/classification
counts/overlay
tumor UNCONFIRMED
no HOT/COLD/EXCLUDED
```

## Scenario D — Unknown MPP

Expected:

```text
cell analysis allowed
pixel coordinates available
micron coordinates null
physical metrics null
TME NOT_ASSESSABLE
```

## Scenario E — Tumor confirmed but insufficient immune evidence

Expected:

```text
tumor PRESENT
available counts stored
TME INDETERMINATE
not EXCLUDED
```

## Scenario F — Benign adenosis regression

For pathologist-confirmed no-tumor/unconfirmed mode:

```text
isolated predicted neoplastic cells may exist
tumor must not auto-promote to PRESENT
TME NOT_APPLICABLE
no treatment-response statement
```

## Scenario G — Cross-tile nucleus

One physical nucleus crossing overlap must become one global instance.

## Scenario H — Worker restart

Queued/in-progress job remains auditable and does not duplicate cell outputs.

## Scenario I — Bundle corruption

Bad checksum prevents worker readiness.

## Scenario J — Local parity

Known fixture reproduces notebook reconstruction/classification/calibration within defined tolerances.

---

# 16. Definition of done

The V2 localization/migration is complete only when:

```text
[ ] final nine-file bundle deployed
[ ] checksums verified at startup
[ ] model.pt fresh-load works
[ ] instance_classifier.pt fresh-load works
[ ] no Internet required
[ ] old Mask2Former not used by V2 path
[ ] original image preserved
[ ] whole-field 256×256 resize removed
[ ] MPP trust explicit
[ ] scale resampling implemented
[ ] 256×256 overlapping tiling implemented
[ ] ImageNet normalization from manifest
[ ] no Macenko mismatch
[ ] seven dense outputs validated
[ ] exact watershed reproduced
[ ] descriptor exactly 132-D
[ ] instance classifier mandatory
[ ] pixel + instance fusion reproduced
[ ] no train-time logit adjustment reapplied
[ ] temperature + class-bias calibration reproduced
[ ] confidence/entropy/margin policy reproduced
[ ] uncertain nuclei preserved
[ ] global stitching implemented
[ ] final counts after stitching
[ ] source coordinates preserved
[ ] micron coordinates only with trusted scale
[ ] notebook/backend parity passes
[ ] clinician tumor/no-tumor/unconfirmed workflow implemented
[ ] tumor-context provenance persisted
[ ] tumor context can be changed without rerunning neural model
[ ] one physical-coordinate spatial engine
[ ] versioned TME policy
[ ] all six TME states supported
[ ] INDETERMINATE never coerced
[ ] NOT_APPLICABLE never coerced
[ ] NOT_ASSESSABLE never coerced
[ ] DB migration/RLS pass
[ ] API auth/pagination pass
[ ] Flutter overlay + uncertainty pass
[ ] reports use deterministic facts
[ ] no unsupported treatment-response claim
[ ] heavy jobs moved to durable worker
[ ] observability/security checks pass
[ ] legacy Mask2Former retired only after cutover tests
```

---

# 17. Final Codex instruction

Implement the already-trained V2 model **exactly**, then build the application around its stable output contract.

The primary correctness sequence is:

```text
correct source image
→ correct physical scale
→ correct 256×256 tile semantics
→ correct TorchScript outputs
→ correct watershed instances
→ correct 132-D classification descriptor
→ correct instance/pixel probability fusion
→ correct calibration/abstention
→ correct cross-tile reconciliation
→ correct pathologist tumor context
→ correct physical spatial measurements
→ correct versioned TME interpretation
→ faithful report
```

Do not solve integration bugs by retraining the model.

Do not simplify the inference path by bypassing:

```text
instance_classifier.pt
calibration.json
postprocess.json
cross-tile stitching
```

Do not make predicted neoplastic cells alone equivalent to a confirmed tumor diagnosis.

The intended application role is:

```text
H&E image
→ AI performs labor-intensive cell segmentation/counting/classification
→ AI produces calibrated, reviewable cell-level evidence
→ pathologist confirms tumor context/ROI
→ system computes reproducible spatial TME measurements
→ system produces a structured TME-oriented report
→ pathologist performs final review/interpretation
```

This is the production target for TME-Insight V2.
