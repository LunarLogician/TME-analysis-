# TME-Insight Pathologist User Manual

**Document version:** 1.0  
**System reviewed:** TME-Insight with deployed nuclei model `tme_nuclei_v2` 2.0.0  
**Review date:** 29 August 2026  
**Primary audience:** Pathologists and authorized clinical users  

---

## Contents

1. [Purpose of this manual](#1-purpose-of-this-manual)
2. [What the system does](#2-what-the-system-does)
3. [Intended use and boundaries](#3-intended-use-and-boundaries)
4. [User roles and access](#4-user-roles-and-access)
5. [Before analyzing a case](#5-before-analyzing-a-case)
6. [Sign in and navigation](#6-sign-in-and-navigation)
7. [Create or select a patient](#7-create-or-select-a-patient)
8. [Start a new biopsy analysis](#8-start-a-new-biopsy-analysis)
9. [Technical image quality control](#9-technical-image-quality-control)
10. [Use the analysis workspace](#10-use-the-analysis-workspace)
11. [Generate and save a report](#11-generate-and-save-a-report)
12. [Reopen a previous analysis](#12-reopen-a-previous-analysis)
13. [Model analysis and validation evidence](#13-model-analysis-and-validation-evidence)
14. [Troubleshooting](#14-troubleshooting)
15. [Pathologist sign-off checklist](#15-pathologist-sign-off-checklist)
16. [Security, privacy, and audit practice](#16-security-privacy-and-audit-practice)
17. [Administrator/operator quick reference](#17-administratoroperator-quick-reference)
18. [Glossary](#18-glossary)
19. [Implementation traceability](#19-implementation-traceability)

## 1. Purpose of this manual

This manual explains how to use the complete TME-Insight system to create a patient record, submit an H&E biopsy image, review AI-detected nuclei, provide pathologist-confirmed tumor context, inspect spatial tumor-microenvironment measurements, and produce a traceable PDF report.

TME-Insight is a **pathologist-assisted quantitative review system**. The deployed model segments and classifies nuclei into five biological classes. It does not independently establish a cancer diagnosis, determine that tumor is present, grade a tumor, assign stage, identify a molecular subtype, or predict treatment response.

> **Clinical safety statement:** Every output must be interpreted with the source H&E image, the full case, morphology, ancillary tests, and local clinical governance. A TME-Insight result must never replace primary histopathological diagnosis or be used alone to select or exclude therapy.

## 2. What the system does

TME-Insight provides an auditable workflow rather than a single black-box label:

1. It checks whether the upload is decodable and has a plausible H&E stain profile.
2. For accepted uploads, it preserves the submitted source image and its checksum and performs technical quality control.
3. It resolves physical scale when reliable microns-per-pixel information is available.
4. It divides tissue into overlapping 256 × 256 pixel tiles.
5. It detects nuclear instances and classifies each as neoplastic, inflammatory, connective, dead, or epithelial.
6. It calibrates the five-class probabilities and marks each nucleus as accepted or uncertain.
7. It stitches overlapping tile results so a nucleus is not intentionally counted once per tile.
8. It asks the pathologist to supply or confirm tumor context.
9. When the required evidence is available, it calculates physical spatial measurements and applies a deterministic TME policy.
10. It stores the results, provenance, overlay, and deterministic PDF report.

The key separation is:

| Evidence layer | Supplied by | Meaning |
| --- | --- | --- |
| Nucleus segmentation and class | AI model | Quantitative candidate finding requiring review |
| Accepted or uncertain state | Calibrated software policy | Whether a model call passes confidence, entropy, and margin rules |
| Tumor present/absent/indeterminate | Pathologist | Human-established tumor context for the analyzed region |
| Spatial measurements | Deterministic calculation | Distances, counts, ratios, and densities from accepted cells |
| HOT/COLD/EXCLUDED state | Deterministic policy | A research/decision-support spatial category, not a treatment-response prediction |

## 3. Intended use and boundaries

### 3.1 Appropriate use

Use TME-Insight to:

- review nuclear segmentation and five-class nuclear phenotypes in an H&E region of interest (ROI);
- keep lower-confidence calls visible rather than silently discarding them;
- quantify accepted neoplastic and inflammatory nuclei;
- calculate physical distances and area-normalized measurements when image scale is trustworthy;
- record whether tumor is present in the whole ROI, absent, or only present within a pathologist-drawn polygon;
- generate a reproducible report containing quality, uncertainty, tumor-context, spatial, model, and run provenance.

### 3.2 Uses that are not supported

Do not use the current release to:

- autonomously diagnose benignity or malignancy;
- treat an accepted “neoplastic” nucleus as proof that the ROI contains tumor;
- interpret the absence of accepted neoplastic nuclei as exclusion of tumor;
- classify a whole slide or a proprietary whole-slide format unless it has first been exported to a locally validated, decodable raster ROI workflow;
- infer intratumoral, peritumoral, or invasive-margin density from fields that are unavailable;
- predict immunotherapy response or recommend treatment;
- compare physical distances or densities when scale is unknown or incorrect;
- generalize performance beyond the validated data without local external validation.

The deployed bundle explicitly contains **no breast-specific tumor-presence gate** and **no TME treatment-response model**. Tumor-dependent interpretation therefore requires pathologist input.

## 4. User roles and access

### 4.1 Clinician/pathologist

The clinician role is the normal pathologist workflow. It can:

- create and review patient records;
- start new biopsy analyses;
- review nuclei and uncertainty;
- confirm or revise tumor context;
- draw a tumor polygon;
- recalculate spatial/TME findings from stored cells;
- generate and save reports;
- access owned patients, sessions, and reports.

### 4.2 Patient

The patient role is read-only and limited to the linked patient record and available completed reports. A patient cannot create a biopsy, change tumor context, or generate a clinical analysis. If a patient account is not linked correctly, an authorized user or administrator must correct the linkage.

### 4.3 Administrator

The administrator role is for system oversight. It can review operational summaries, user records, and aggregate analytics. It is not a substitute for the clinician role and must not be used to make diagnostic decisions from operational dashboards.

Public registration creates clinician accounts only. Administrator or patient status must be assigned through the trusted account-management process. Role metadata must never be changed solely from an untrusted client request.

## 5. Before analyzing a case

### 5.1 Confirm case and image suitability

Before upload, confirm that:

- the selected patient is correct;
- the image represents the intended case and ROI;
- the section is H&E and sufficiently well focused for nuclear assessment;
- the field contains enough tissue and is not dominated by blank background;
- major folds, crushing, cautery, pen, debris, out-of-focus regions, or exposure problems have not made the ROI non-representative;
- microns-per-pixel (MPP) is known from scanner metadata or another validated source if physical TME measurements are required;
- the ROI selection and any image export comply with local specimen, privacy, and validation procedures.

Prefer a lossless, decodable RGB raster export such as a locally validated PNG or TIFF. JPEG may introduce compression artifacts. The current upload path is designed for an H&E patch/ROI, not for direct navigation of a proprietary whole-slide image.

### 5.2 Understand physical scale

The deployed model expects approximately **0.25 µm/pixel (40× equivalent)**. If reliable source MPP is available, the pipeline can use it to place measurements in physical coordinates and resample for model inference.

Do not estimate MPP by eye. If metadata is absent and no validated value is known, leave the MPP field blank. The model can still produce pixel-space nuclear findings, but physical distances and densities are withheld and the TME state becomes `NOT_ASSESSABLE`.

## 6. Sign in and navigation

1. Open TME-Insight.
2. Enter the authorized account email and password.
3. Select **Sign in**.
4. Confirm that the navigation matches the assigned role.

For a clinician, the main navigation contains:

- **Home** — workload summary and recent sessions;
- **Patients** — patient roster and case history;
- **New biopsy** — image upload and analysis configuration;
- **Reports** — completed analysis history;
- **Profile** — account, role, session information, and sign out.

Always sign out on a shared workstation. Downloaded reports become local files and must be handled according to institutional policy.

## 7. Create or select a patient

### 7.1 Create a patient

1. Open **Patients** or use **Add New Patient** from Home.
2. Enter the patient’s full name.
3. Enter the date of birth. The current form accepts adult patients aged 18 years or older.
4. Select gender: Female, Male, or Other.
5. Enter the diagnosis/history note. This is required and is limited to 500 characters.
6. Save the record.

Use the institutionally approved identifier convention. Avoid duplicate records. The diagnosis/history field is clinician-supplied context, not a model result.

### 7.2 Select an existing patient

1. Open **Patients**.
2. Search the roster.
3. Open the patient record.
4. Check demographics, clinical note, and previous sessions.
5. Select **New biopsy** to begin from that record, or open an existing completed session.

## 8. Start a new biopsy analysis

### 8.1 Select and preview the image

1. Open **New biopsy**.
2. Select the correct patient from the dropdown.
3. Select **Choose biopsy image from device**.
4. Choose **gallery** or **camera**.
5. Inspect the preview and filename.

The upload first passes a local, deterministic H&E compatibility screen. Natural photographs, grayscale images, brown IHC images, and other unsupported sources are rejected before an image asset or analysis run is created. No remote LLM is used and there is no manual “accept anyway” action. This screen checks stain compatibility; it cannot prove specimen provenance or replace pathologist confirmation that the image is the correct biopsy.

For accepted uploads, the original submitted bytes are preserved without intentional client-side resizing or recompression. The default maximum upload size is **100 MB**. If the wrong image is selected, remove it before starting. Once a source asset has been created, it is immutable; use a new analysis session for a different source image.

### 8.2 Choose the analysis mode

Select one of the three modes:

| Interface option | Internal state | Use when |
| --- | --- | --- |
| **Nuclei only — tumor unconfirmed** | `NUCLEI_ONLY` | Tumor context has not yet been established for this ROI. This is the safest default. |
| **Confirm tumor in whole ROI** | `PATHOLOGIST_CONFIRMED_TME` | You have reviewed the source image and can attest that the whole analyzed tissue ROI is tumor context. |
| **Confirm no tumor** | `NO_TUMOR` | You have reviewed the ROI and can attest that tumor is absent from it. |

“Confirm tumor” is a pathologist assertion; it is not derived from the nuclei model. If tumor occupies only part of the ROI, start as nuclei-only and draw a polygon in the **Tumor context** section after analysis.

### 8.3 Enter MPP

- Leave the field blank if trustworthy metadata is expected in the image.
- If metadata is absent, enter a positive MPP value only when obtained from a validated scanner/export source.
- The current interface applies the entered value to both X and Y axes.

Incorrect MPP changes all physical distances and areas and can change the HOT/COLD/EXCLUDED state. If an analysis was run with missing or incorrect scale, create a new analysis with the correct validated MPP rather than inventing or retrospectively guessing it.

### 8.4 Run the analysis

1. Recheck patient, image, mode, and MPP.
2. Select **Start TME-Insight Analysis**.
3. Keep the application open while the run is submitted and progress is shown.

Typical internal stages include validation, metadata reading, resampling, tissue masking, tiling, nuclear inference, instance reconstruction, calibration, tile stitching, cell persistence, spatial analysis, TME interpretation, and artifact rendering.

If the network drops or the screen appears stalled, first check the patient record or Reports for an existing session before submitting the image again.

## 9. Technical image quality control

The Overview section reports `PASS`, `WARNING`, or `FAIL`.

- **PASS** — no configured technical warning or failure was detected.
- **WARNING** — analysis may proceed, but a possible issue requires review.
- **FAIL** — one or more configured failure rules were met; normal inference is stopped.

Current automated checks include image dimensions, decodable RGB channels, H&E stain compatibility, estimated tissue fraction, a Laplacian-based blur score, extreme exposure, and scale availability. The H&E gate combines `rgb2hed` colour deconvolution with chromatic and purple/magenta stain evidence. Eosin is recorded as a QC metric but is not mandatory because lightly stained H&E patches may contain little measurable eosin.

The implemented technical thresholds are:

| Check | Warning | Failure |
| --- | ---: | ---: |
| Minimum image dimension | — | less than 64 px |
| Estimated tissue fraction | — | less than 1% |
| Chromatic tissue fraction | — | less than 5% |
| Purple/magenta stain hue fraction | — | less than 20% of chromatic tissue |
| Hematoxylin-positive tissue fraction | — | less than 15% |
| Non-H&E stain-channel mean | — | above 0.10 |
| Blur variance | below 35 | below 5 |
| Extreme exposure fraction | above 35% | above 80% |
| Physical scale | unknown | does not stop nuclei inference, but blocks physical TME assessment |

These are software screening thresholds, not histological acceptability criteria. A `PASS` does not establish that an ROI is representative, and a `WARNING` must be reconciled with visual review.

Common reason codes include:

- `POSSIBLE_BLUR`
- `POSSIBLE_EXPOSURE_ISSUE`
- `PHYSICAL_SCALE_UNKNOWN`
- `IMAGE_DIMENSIONS_TOO_SMALL`
- `INSUFFICIENT_TISSUE`
- `UNSUPPORTED_NON_HE_IMAGE`
- `GROSS_BLUR`
- `GROSS_EXPOSURE`
- `UNSUPPORTED_CHANNELS`

## 10. Use the analysis workspace

The review workspace is divided into **Overview**, **Nuclei**, **Tumor context**, **TME interpretation**, and **Report**. On a wide screen, use the side navigation. On a smaller screen, use the section dropdown.

### 10.1 Overview

Use Overview as the triage page. It displays:

- detected, accepted, and uncertain nucleus totals;
- current TME state;
- image quality and physical scale status;
- expandable warnings;
- class distribution;
- the recommended review pathway.

Do not approve a case from the headline cards alone. Review quality, uncertainty, overlay, tumor context, and spatial evidence.

### 10.2 Nuclei

The Nuclei section provides an overlay and a cell explorer.

1. Pan and zoom through the overlay.
2. Compare nuclear boundaries and labels with the underlying H&E morphology.
3. Filter the cell list by biological class and acceptance state.
4. Sort by confidence, class, or area.
5. Select a nucleus to inspect its details.

The cell detail panel can show:

- predicted class;
- accepted or uncertain status;
- calibrated confidence;
- normalized entropy;
- top-one versus top-two probability margin;
- nuclear area;
- pixel centroid;
- micron centroid when scale is valid;
- probabilities for all five biological classes.

The overlay is a pre-rendered, full-field artifact. Current list filters refine the cell explorer; they do not redraw or hide objects in the overlay. Counts are produced after cross-tile stitching.

#### Biological classes

| Class | Intended model label | Pathologist review emphasis |
| --- | --- | --- |
| Neoplastic | Tumor-type nucleus | Confirm against architecture and cytology; do not equate a call with proof of tumor. |
| Inflammatory | Immune/inflammatory nucleus | Review small dark nuclei, crush, apoptotic material, and overlapping cells. |
| Connective | Stromal/connective nucleus | Review spindle cells, fibroblasts, endothelial-like profiles, and overlap. |
| Dead | Dead/necrotic nuclear material | Treat cautiously; this is the weakest evaluated class in the release. |
| Epithelial | Non-neoplastic epithelial-type nucleus | Review benign glands and epithelial mimics in case context. |

`UNCERTAIN` is not a sixth biological class. It is an application state assigned when a class prediction does not pass all acceptance rules.

### 10.3 Accepted versus uncertain nuclei

A nucleus is accepted only if all of the following are true:

- its calibrated top-class probability reaches the class-specific minimum;
- normalized entropy is no greater than 0.85;
- the top-one/top-two probability margin is at least 0.05.

The minimum confidence is 0.95 for neoplastic nuclei and 0.55 for each other class. A nucleus that fails any rule remains uncertain and visible for audit.

Spatial TME calculations use **accepted** nuclei. Consequently, a strict acceptance threshold can reduce the neoplastic count and may make an analysis indeterminate. Review the uncertain population before accepting the quantitative summary.

### 10.4 Tumor context

The Tumor context section records the pathologist’s interpretation separately from the model.

Choose:

- **Present** — tumor is confirmed in the analyzed context;
- **Absent** — no tumor is confirmed in the ROI;
- **Indeterminate** — tumor has not been confirmed for this analysis.

For tumor present, choose the appropriate region mode:

- **Whole ROI** when the complete analyzed tissue region can be treated as tumor context.
- **Polygon** when tumor occupies only a defined part of the image.

To draw a polygon:

1. Select the tumor-region drawing control.
2. Tap at least three boundary points around the tumor region.
3. Use Undo if a point is misplaced.
4. Confirm the polygon.
5. Verify the updated region and provenance.

Changing tumor context recalculates spatial and TME results from the persisted nucleus set; it does **not** rerun the neural network. The system records evidence source, region mode, confirming user, and timestamp.

Only confirm tumor status after reviewing the H&E. If morphology is equivocal, leave it indeterminate and resolve the diagnosis through the normal pathology workflow.

### 10.5 TME interpretation

The TME section displays the state, underlying measurements, policy version, and reason codes.

The current `tme-policy-v1.1` requires:

1. image QC that has not failed;
2. trusted physical scale;
3. pathologist-confirmed tumor presence;
4. available spatial measurements;
5. at least three accepted neoplastic nuclei;
6. at least three accepted inflammatory nuclei.

When these conditions are met, the policy uses the **mean nearest-neighbor distance from each accepted neoplastic nucleus to the nearest accepted inflammatory nucleus**:

| Mean distance | Policy state |
| ---: | --- |
| less than 20 µm | `HOT` |
| 20–60 µm inclusive | `EXCLUDED` |
| greater than 60 µm | `COLD` |

The displayed policy score is an implementation aid derived from distance. It is **not a probability**, risk score, biomarker result, or prediction of response to immunotherapy.

Other possible states are:

| State | Meaning in this system |
| --- | --- |
| `INDETERMINATE` | Tumor is present but accepted-cell or spatial evidence is insufficient for a stable category. |
| `NOT_ASSESSABLE` | A technical prerequisite failed, most commonly failed QC or unknown physical scale. |
| `NOT_APPLICABLE` | After technical prerequisites pass, tumor is absent or remains unconfirmed, so a tumor-dependent category is not applied. |

The implemented policy checks quality and scale before tumor state. Therefore an image with unknown scale remains `NOT_ASSESSABLE` even if tumor has been marked absent.

#### Current spatial measurements

When available, the system may report:

- accepted neoplastic and inflammatory counts;
- accepted and uncertain counts for all five classes;
- tissue area in mm²;
- tumor area in mm² for a whole-ROI or polygon region;
- neoplastic density per tissue mm²;
- inflammatory density per tissue mm²;
- inflammatory-to-neoplastic ratio;
- neoplastic-to-inflammatory nearest distances: mean, median, 25th percentile, and 75th percentile;
- inflammatory-to-neoplastic nearest distances: mean and median.

In the current release, the main neoplastic and inflammatory density fields use **total tissue area** as the denominator. Intratumoral immune density, peritumoral immune density, and boundary-infiltration score are reserved fields and are not currently calculated. Do not infer them from the tumor polygon or from unavailable values.

## 11. Generate and save a report

1. Open the **Report** section after completing review.
2. Confirm that quality, scale, nucleus counts, uncertainty, tumor provenance, spatial measurements, and TME state are coherent.
3. Select **Generate/refresh report**.
4. Select **Save PDF** and store it only in an approved location.

The PDF is deterministic and is generated from persisted facts. It contains:

1. clinician-supplied clinical information;
2. image quality and physical scale;
3. AI nucleus counts;
4. accepted and uncertain counts;
5. tumor-context provenance;
6. spatial measurements;
7. TME policy state and reasons;
8. limitations and warnings;
9. model name, version, architecture, and checkpoint hash.

The current reporting path does **not** use LangChain, Gemini, or another generative language model. It deliberately avoids generated diagnostic prose and treatment claims. Report generation does not alter cell counts, tumor context, spatial results, or the TME state.

Before using the PDF outside the system, confirm patient identity, source case, tumor assertion, warning text, and report generation time. The report is a quantitative decision-support attachment, not a signed diagnostic pathology report unless local governance explicitly integrates it into an approved reporting process.

## 12. Reopen a previous analysis

Use either:

- **Reports** to see completed biopsy sessions and open an analysis; or
- **Patients → Patient details** to review the patient’s session history.

A completed session can be reopened for review. A processing session may not yet expose results. A legacy or incomplete session may display “No analysis available”; do not interpret missing analysis data as a negative result. Contact the administrator if a session should have results but does not.

## 13. Model analysis and validation evidence

### 13.1 Deployed model

| Item | Current bundle |
| --- | --- |
| Internal model identity | `tme_nuclei_v2` 2.0.0 |
| Architecture | ResNet-34/Transformer HoVer-style nuclei model with seed, contour, feature, and within-patch global-context outputs |
| Framework | PyTorch/TorchScript |
| Training data | PanNuke |
| Held-out evaluation | PanNuke outer test fold 3, 2,722 images |
| Input patch | 256 × 256 px |
| Expected scale | 0.25 µm/px, approximately 40× |
| Biological classes | Neoplastic, inflammatory, connective, dead, epithelial |
| Stain normalization | Not required by the bundle; stain augmentation was used in training |
| Tumor-presence gate | Not included |
| Treatment-response prediction | Not included |

For each candidate instance, the deployed post-processing combines pixel evidence with a learned 132-dimensional instance descriptor: 32 interior features, 32 surrounding-ring features, 64 within-patch context features, and 4 shape features. The resulting probabilities are fused, calibrated, subjected to acceptance rules, and stitched across overlapping tiles.

### 13.2 Held-out results

Dataset-level held-out PanNuke results were:

| Metric | Result |
| --- | ---: |
| Binary panoptic quality (bPQ) | 0.6503 |
| Mean panoptic quality (mPQ) | 0.5027 |
| Detection quality / Detection F1 | 0.7906 |
| Segmentation quality (SQ) | 0.8225 |
| Dice | 0.8351 |
| AJI+ | 0.6952 |

Per-class panoptic performance was:

| Class | Precision | Recall | F1 | PQ |
| --- | ---: | ---: | ---: | ---: |
| Neoplastic | 0.7149 | 0.7232 | 0.7190 | 0.6000 |
| Inflammatory | 0.6923 | 0.6732 | 0.6826 | 0.5724 |
| Connective | 0.6216 | 0.5549 | 0.5864 | 0.4712 |
| Dead | 0.4136 | 0.3169 | 0.3589 | 0.2658 |
| Epithelial | 0.7245 | 0.7599 | 0.7418 | 0.6042 |

Among matched held-out nuclei, calibrated accepted-call coverage was 0.7171 and accuracy among accepted matched nuclei was 0.9043. Held-out matched expected calibration error was 0.0121.

The separate internal-validation operating point for the 0.95 neoplastic acceptance threshold achieved precision 0.8565, recall 0.4627, and coverage 0.1691. This conservative gate prioritizes precision at the cost of recall. It explains why apparently neoplastic nuclei may remain uncertain and why absence of accepted neoplastic calls cannot exclude tumor.

These metrics answer different technical questions and must not be read as patient-level sensitivity, specificity, positive predictive value, or clinical outcome performance.

### 13.3 Clinical implications of the evidence

- PanNuke is a multi-tissue nucleus dataset; it does not provide a validated breast benign-versus-malignant tumor-presence target.
- External breast hard-negative validation has not been performed for this bundle.
- The dead class has the weakest evaluated panoptic performance, followed by connective tissue relative to the strongest classes.
- Performance must be checked locally across scanners, stains, magnifications, preparation artifacts, tissue types, and relevant case mix.
- Required future validation includes benign breast specificity, false neoplastic nuclei per mm², adenosis/sclerosing-adenosis behavior, false tumor-gate positives, and scanner/stain/magnification stratification.
- HOT/COLD/EXCLUDED thresholds are deterministic policy boundaries; they are not validated treatment-response endpoints.

Until local clinical validation and governance are complete, use the system for controlled research, evaluation, or explicitly approved decision support—not autonomous clinical deployment.

## 14. Troubleshooting

| Problem | What to check | Safe response |
| --- | --- | --- |
| Upload rejected | File empty, over 100 MB, undecodable, unsupported channel layout, or not compatible with an H&E-stained sample | Verify the source is the intended H&E biopsy ROI and export a supported colour raster without changing its clinical meaning. |
| Analysis says resource temporarily unavailable | Worker/thread resource exhaustion, process limits, or service restart | Wait for the backend to recover, check whether the session already exists, then retry once. Escalate repeated failures to the administrator. |
| QC warning | Blur, exposure, or missing scale | Review the H&E directly. Use a better ROI/export if technically unsuitable. Never dismiss a warning solely because the run completed. |
| QC failure | Too small, insufficient tissue, gross blur/exposure, unsupported channels, or failed H&E compatibility | Do not interpret the run. Correct the source image or select a suitable H&E ROI. |
| TME is `NOT_ASSESSABLE` | Failed QC or unknown/untrusted physical scale | Resolve the technical prerequisite. For missing scale, create a new analysis with validated MPP. |
| TME is `NOT_APPLICABLE` | Tumor absent or not confirmed, after technical prerequisites pass | Review tumor context. Confirm only what is supported by morphology. |
| TME is `INDETERMINATE` | Too few accepted neoplastic/inflammatory cells or missing spatial evidence | Review uncertain cells and ROI representativeness; do not force a category. |
| Counts look implausible | Artifact, wrong scale/export, model domain shift, overlap, weak class performance | Compare overlay with H&E, document discrepancy, and do not use the quantitative conclusion uncritically. |
| Micron values are absent | Scale was not resolved | Do not convert pixels manually unless the conversion is validated; rerun as a new analysis with correct MPP. |
| Wrong image was attached | Session source is immutable | Start a new biopsy session with the correct image. Do not relabel the old source as another case. |
| Screen/network interruption | Client disconnected while backend continued | Check patient/session history before re-uploading to avoid duplicate runs. |
| Report is unavailable or outdated | Run incomplete or tumor context changed after an earlier report | Complete review, then generate/refresh the report. |
| Access denied | Wrong role, expired sign-in, or ownership policy | Sign in again and contact an administrator; do not share another user’s account. |

## 15. Pathologist sign-off checklist

Before accepting or exporting a TME-Insight result, confirm:

- [ ] Correct patient and case were selected.
- [ ] The submitted image is the intended H&E ROI.
- [ ] ROI representativeness was assessed by a pathologist.
- [ ] QC status and every warning/failure were reviewed.
- [ ] MPP source is trustworthy if physical measurements are used.
- [ ] Overlay alignment and a representative sample of nuclei were reviewed.
- [ ] Uncertain nuclei and plausible classification errors were considered.
- [ ] Tumor status and region were explicitly confirmed by morphology.
- [ ] Accepted neoplastic nuclei were not treated as autonomous proof of tumor.
- [ ] The TME state was reconciled with counts, distances, and reason codes.
- [ ] No unavailable spatial field was inferred or reported.
- [ ] HOT/COLD/EXCLUDED was not described as treatment-response prediction.
- [ ] The deterministic PDF matches the reviewed on-screen result.
- [ ] Any discrepancy or limitation is documented under local policy.

## 16. Security, privacy, and audit practice

- Use only an individually assigned account.
- Keep patient data within approved devices, networks, storage, and retention policies.
- Do not share screenshots or downloaded PDFs through unapproved channels.
- Sign out after use on shared devices.
- Preserve the source image/run/report linkage when exporting evidence.
- Do not alter the model bundle, calibration, MPP, tumor context, or report outside the authorized workflow.
- Report suspected cross-patient access, incorrect role assignment, or provenance mismatch immediately.

The application uses authenticated access, ownership-aware database policies, immutable source-asset linkage, persisted model/checkpoint provenance, and timestamped tumor confirmation. These controls support auditability but do not replace institutional governance.

## 17. Administrator/operator quick reference

This section is for authorized technical staff, not routine pathologist use.

### 17.1 Required services

- Supabase/PostgreSQL schema and row-level security migrations;
- backend API;
- model bundle and checksum-validating loader;
- artifact storage;
- Redis/RQ worker in production, or the limited development executor in a local development profile;
- Flutter client configured for the intended API and Supabase project.

### 17.2 Database order

For a clean database, apply migrations in order:

1. `Backend/migrations/20260826_core_schema.sql`
2. `Backend/migrations/20260827_tme_insight_v2.sql`

Confirm that the core analysis tables, ownership relations, indexes, grants, and RLS policies exist before clinical testing. Never expose the Supabase service-role key in the Flutter application.

### 17.3 Local launch outline

From the project root, an authorized developer normally starts the backend from `Backend` with the configured Python environment and then runs the Flutter client from `Frontend`. Production must use the approved process manager and queue worker rather than a development `--reload` process.

Before allowing manual testing, confirm:

- model bundle startup validation passes;
- backend health and authenticated endpoints respond;
- worker queue is available;
- Supabase authentication and RLS are functioning;
- artifact directories are writable by the service only as intended;
- frontend API/Supabase configuration points to the test environment;
- no production patient data is used in an unapproved development environment.

## 18. Glossary

| Term | Meaning |
| --- | --- |
| Accepted nucleus | A model class call that passes confidence, entropy, and probability-margin rules. |
| Uncertain nucleus | A biological class prediction retained for review because it fails at least one acceptance rule. |
| MPP | Microns per pixel; the physical scale of the source image. |
| ROI | Region of interest submitted for analysis. |
| TME | Tumor microenvironment. |
| Nearest-neighbor distance | Distance from one accepted cell to the closest accepted target-class cell. |
| Panoptic quality (PQ) | A combined instance-detection and segmentation-quality metric. |
| Calibration | Adjustment of model probability estimates to the validated operating policy. |
| Abstention | Keeping a prediction uncertain instead of treating it as accepted. |
| Provenance | Stored evidence of source image, user action, model/checkpoint, policy, and time. |

## 19. Implementation traceability

This manual was cross-checked against the deployed implementation and bundle records, principally:

- [`model_manifest.json`](../Backend/app/model_weights/tme_nuclei_v2/model_manifest.json)
- [`calibration.json`](../Backend/app/model_weights/tme_nuclei_v2/calibration.json)
- [`postprocess.json`](../Backend/app/model_weights/tme_nuclei_v2/postprocess.json)
- [`model_release_report.md`](../Backend/app/model_weights/tme_nuclei_v2/model_release_report.md)
- [`quality_service.py`](../Backend/app/services/quality_service.py)
- [`spatial_engine.py`](../Backend/app/services/spatial_engine.py)
- [`tme_policy.py`](../Backend/app/services/tme_policy.py)
- [`report_service.py`](../Backend/app/services/report_service.py)
- [`analysis_workspace.dart`](../Frontend/lib/widgets/analysis/analysis_workspace.dart)
- [`ARCHITECTURE.md`](ARCHITECTURE.md)

If the model, calibration, TME policy, user interface, or database schema changes, this manual must be reviewed and versioned before the updated system is used.
