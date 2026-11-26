# TME-Insight

**Pathologist-assisted H&E nuclei and spatial TME decision support**

TME-Insight preserves the original H&E source, runs the localized `tme_nuclei_v2` TorchScript bundle over overlapping 256×256 tiles, reconstructs and calibrates reviewable nuclei, and lets a pathologist confirm tumor context before physical spatial TME interpretation. It does not infer tumor presence from predicted neoplastic nuclei alone and does not predict treatment response.

## Architecture

See the [detailed system architecture](docs/ARCHITECTURE.md) for the full runtime, analysis/report sequences, data model, RBAC boundaries, and API map.

- **Frontend**: Flutter + Riverpod upload, real-stage progress, uncertainty/cell review, tumor-context annotation, and six-state TME display.
- **Backend**: FastAPI with JWT/ownership enforcement, immutable source assets, a paginated analysis API, and deterministic reports.
- **ML pipeline**:
  - checksum-verified `model.pt` and `instance_classifier.pt`;
  - manifest-sourced ImageNet normalization, scale handling, and overlapping tiling;
  - configured watershed, exact 132-D typing descriptor, pixel/instance fusion, calibration/abstention, and global stitching;
  - no Internet, Hugging Face, pretrained download, or Macenko dependency.
- **Workers**: one Redis/RQ durable queue in production; job payloads carry IDs only.
- **Database**: Supabase (PostgreSQL) with Row Level Security (RLS) ensuring strict data isolation per clinician.

## Setup & Installation

### Backend

1. Navigate to the `Backend` directory:
   ```bash
   cd Backend
   ```
2. Set up the virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```
3. Configure environment variables in `.env`:
   ```env
   SUPABASE_URL=your_supabase_url
   SUPABASE_SERVICE_KEY=your_service_role_key
   SUPABASE_JWT_SECRET=your_jwt_verification_secret
   TME_V2_BUNDLE_PATH=app/model_weights/tme_nuclei_v2
   TME_ANALYSIS_QUEUE=development
   ```
4. For a new Supabase project, apply `Backend/migrations/20260826_core_schema.sql`, then `Backend/migrations/20260827_tme_insight_v2.sql`.
5. Production only: configure `REDIS_URL`, set `TME_ANALYSIS_QUEUE=rq`, and run an RQ worker for `tme-analysis`.
6. Run the API server:
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

### Frontend

1. Navigate to the `Frontend` directory:
   ```bash
   cd Frontend
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

## Key Features

- **RBAC & Multi-Tenancy**: Secure clinician-specific patient management.
- **Explicit scale trust**: nuclei analysis remains available with unknown MPP, while invalid physical metrics are withheld.
- **Automatic H&E gate**: local stain-deconvolution and colour checks reject natural photographs, grayscale images, and incompatible stains before persistence or inference.
- **Reviewable uncertainty**: calibrated five-class probabilities and acceptance state are retained per nucleus.
- **Pathologist tumor context**: whole ROI, annotated region, confirmed no tumor, or unconfirmed nuclei-only.
- **Canonical TME vocabulary**: HOT, COLD, EXCLUDED, INDETERMINATE, NOT_ASSESSABLE, and NOT_APPLICABLE.
- **Structured PDF reports**: deterministic facts and provenance without unsupported diagnosis or treatment-response claims.

### Role boundaries

- **Clinician**: owns patient records, creates biopsy sessions, runs image analysis, and reviews or generates clinical reports. Patient access is restricted by `clinician_id` and RLS.
- **Administrator**: monitors platform-wide session volume, phenotype distribution, and clinician activity. Administrators can read across tenants for operational oversight but do not act as the treating clinician.
- **Patient**: can only read the patient record linked to their authenticated account and its sessions.

Administrator accounts must be assigned through trusted Supabase admin metadata; public registration creates clinician accounts only. This keeps user-editable metadata from granting administrative access.

### Demo data

The seed script creates 10 deterministic BreaKHis-inspired patient records. Run it with an existing clinician UUID:

```bash
cd Backend
SEED_CLINICIAN_ID=<clinician-uuid> ./venv/bin/python scripts/seed_patients.py
```

## Testing

The focused backend suite includes bundle, preprocessing, post-processing, calibration, stitching, domain, spatial/TME, persistence, and report tests.
```bash
cd Backend && source venv/bin/activate
python -m pytest tests/v2 -q
```

Frontend UI tests and end-to-end integration:
```bash
cd Frontend
flutter test
```
# TME-analysis-
