-- TME-Insight analysis schema. Apply after 20260826_core_schema.sql.
BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS model_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_name TEXT NOT NULL,
    version TEXT NOT NULL,
    architecture TEXT NOT NULL,
    checkpoint_sha256 TEXT NOT NULL CHECK (checkpoint_sha256 ~ '^[a-f0-9]{64}$'),
    manifest_json JSONB NOT NULL,
    calibration_version TEXT NOT NULL,
    postprocess_version TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (model_name, version, checkpoint_sha256)
);

CREATE UNIQUE INDEX IF NOT EXISTS one_active_tme_model
    ON model_versions ((active)) WHERE active;

CREATE TABLE IF NOT EXISTS image_assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES biopsy_sessions(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    sha256 TEXT NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
    mime_type TEXT NOT NULL,
    width_px INTEGER NOT NULL CHECK (width_px > 0),
    height_px INTEGER NOT NULL CHECK (height_px > 0),
    mpp_x DOUBLE PRECISION CHECK (mpp_x > 0),
    mpp_y DOUBLE PRECISION CHECK (mpp_y > 0),
    magnification DOUBLE PRECISION CHECK (magnification > 0),
    scale_source TEXT NOT NULL CHECK (scale_source IN (
        'WSI_METADATA', 'TIFF_METADATA', 'USER_PROVIDED',
        'MAGNIFICATION_POLICY', 'UNKNOWN'
    )),
    scale_trusted BOOLEAN NOT NULL DEFAULT FALSE,
    metadata_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session_id, sha256)
);

CREATE TABLE IF NOT EXISTS analysis_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES biopsy_sessions(id) ON DELETE CASCADE,
    image_asset_id UUID NOT NULL REFERENCES image_assets(id) ON DELETE RESTRICT,
    model_version_id UUID REFERENCES model_versions(id) ON DELETE RESTRICT,
    status TEXT NOT NULL CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETE', 'FAILED')),
    stage TEXT NOT NULL CHECK (stage IN (
        'QUEUED', 'VALIDATING_IMAGE', 'READING_METADATA', 'RESAMPLING',
        'TISSUE_MASKING', 'TILING', 'NUCLEAR_INFERENCE',
        'INSTANCE_RECONSTRUCTION', 'CALIBRATION', 'STITCHING',
        'PERSISTING_CELLS', 'AWAITING_TUMOR_CONTEXT', 'SPATIAL_ANALYSIS',
        'TME_INTERPRETATION', 'RENDERING_ARTIFACTS', 'COMPLETE', 'FAILED'
    )),
    progress DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 1),
    quality_status TEXT CHECK (quality_status IN ('PASS', 'WARNING', 'FAIL')),
    effective_mpp_x DOUBLE PRECISION CHECK (effective_mpp_x > 0),
    effective_mpp_y DOUBLE PRECISION CHECK (effective_mpp_y > 0),
    tile_count INTEGER NOT NULL DEFAULT 0 CHECK (tile_count >= 0),
    processed_tile_count INTEGER NOT NULL DEFAULT 0 CHECK (processed_tile_count >= 0),
    accepted_cell_count INTEGER NOT NULL DEFAULT 0 CHECK (accepted_cell_count >= 0),
    uncertain_cell_count INTEGER NOT NULL DEFAULT 0 CHECK (uncertain_cell_count >= 0),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    failure_code TEXT,
    failure_message TEXT,
    config_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    output_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS analysis_runs_session_created_idx
    ON analysis_runs (session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS analysis_runs_status_created_idx
    ON analysis_runs (status, created_at);

CREATE TABLE IF NOT EXISTS cell_instances (
    analysis_run_id UUID NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    instance_id UUID NOT NULL,
    class_name TEXT NOT NULL CHECK (class_name IN (
        'NEOPLASTIC', 'INFLAMMATORY', 'CONNECTIVE', 'DEAD', 'EPITHELIAL'
    )),
    class_id INTEGER NOT NULL CHECK (class_id BETWEEN 1 AND 5),
    centroid_x_px DOUBLE PRECISION NOT NULL,
    centroid_y_px DOUBLE PRECISION NOT NULL,
    centroid_x_um DOUBLE PRECISION,
    centroid_y_um DOUBLE PRECISION,
    area_px DOUBLE PRECISION NOT NULL CHECK (area_px > 0),
    area_um2 DOUBLE PRECISION CHECK (area_um2 > 0),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    entropy DOUBLE PRECISION NOT NULL CHECK (entropy BETWEEN 0 AND 1),
    margin DOUBLE PRECISION NOT NULL CHECK (margin BETWEEN 0 AND 1),
    segmentation_confidence DOUBLE PRECISION CHECK (segmentation_confidence BETWEEN 0 AND 1),
    acceptance_status TEXT NOT NULL CHECK (acceptance_status IN ('ACCEPTED', 'UNCERTAIN', 'REJECTED')),
    probabilities JSONB NOT NULL CHECK (jsonb_array_length(probabilities) = 5),
    bbox JSONB NOT NULL CHECK (jsonb_array_length(bbox) = 4),
    source_tile_ids JSONB NOT NULL,
    tumor_membership BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (analysis_run_id, instance_id)
);

CREATE INDEX IF NOT EXISTS cell_instances_run_class_idx
    ON cell_instances (analysis_run_id, class_name, acceptance_status);

CREATE TABLE IF NOT EXISTS tumor_assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_run_id UUID NOT NULL UNIQUE REFERENCES analysis_runs(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('PRESENT', 'ABSENT', 'INDETERMINATE')),
    evidence_source TEXT NOT NULL CHECK (evidence_source IN (
        'CLINICIAN_CONFIRMED_TUMOR', 'CLINICIAN_CONFIRMED_NO_TUMOR',
        'UNCONFIRMED_NUCLEI_ONLY', 'VALIDATED_AI_TUMOR_GATE'
    )),
    confirmed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    confirmed_at TIMESTAMPTZ,
    tumor_region_mode TEXT CHECK (tumor_region_mode IN ('WHOLE_ROI', 'ANNOTATED_REGION', 'NONE')),
    tumor_region_artifact_id UUID,
    confident_neoplastic_count INTEGER NOT NULL DEFAULT 0,
    uncertain_neoplastic_count INTEGER NOT NULL DEFAULT 0,
    neoplastic_density_mm2 DOUBLE PRECISION,
    spatial_coherence_score DOUBLE PRECISION,
    reason_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS spatial_analysis_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_run_id UUID NOT NULL UNIQUE REFERENCES analysis_runs(id) ON DELETE CASCADE,
    measurement_version TEXT NOT NULL,
    metrics JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tme_assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_run_id UUID NOT NULL UNIQUE REFERENCES analysis_runs(id) ON DELETE CASCADE,
    state TEXT NOT NULL CHECK (state IN (
        'HOT', 'COLD', 'EXCLUDED', 'INDETERMINATE',
        'NOT_ASSESSABLE', 'NOT_APPLICABLE'
    )),
    policy_version TEXT NOT NULL,
    score DOUBLE PRECISION CHECK (score BETWEEN 0 AND 1),
    reason_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    input_measurement_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analysis_artifacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_run_id UUID NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL CHECK (artifact_type IN (
        'overlay', 'cells_geojson', 'cells_parquet', 'tissue_mask',
        'tumor_region', 'diagnostics', 'report'
    )),
    storage_path TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (analysis_run_id, artifact_type)
);

ALTER TABLE tumor_assessments
    DROP CONSTRAINT IF EXISTS tumor_assessments_tumor_region_artifact_id_fkey;
ALTER TABLE tumor_assessments
    ADD CONSTRAINT tumor_assessments_tumor_region_artifact_id_fkey
    FOREIGN KEY (tumor_region_artifact_id)
    REFERENCES analysis_artifacts(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE model_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE image_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE analysis_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE cell_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE tumor_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE spatial_analysis_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE tme_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE analysis_artifacts ENABLE ROW LEVEL SECURITY;

-- Ownership flows through analysis_runs -> biopsy_sessions -> patients.
CREATE OR REPLACE FUNCTION public.can_access_analysis(target_run UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM analysis_runs ar
        JOIN biopsy_sessions bs ON bs.id = ar.session_id
        JOIN patients p ON p.id = bs.patient_id
        JOIN users u ON u.id = auth.uid()
        WHERE ar.id = target_run
          AND (p.clinician_id = auth.uid() OR p.patient_user_id = auth.uid() OR u.role = 'admin')
    );
$$;

DROP POLICY IF EXISTS "Authorized users read analysis runs" ON analysis_runs;
CREATE POLICY "Authorized users read analysis runs" ON analysis_runs FOR SELECT
    USING (public.can_access_analysis(id));
DROP POLICY IF EXISTS "Authorized users read cells" ON cell_instances;
CREATE POLICY "Authorized users read cells" ON cell_instances FOR SELECT
    USING (public.can_access_analysis(analysis_run_id));
DROP POLICY IF EXISTS "Authorized users read tumor assessments" ON tumor_assessments;
CREATE POLICY "Authorized users read tumor assessments" ON tumor_assessments FOR SELECT
    USING (public.can_access_analysis(analysis_run_id));
DROP POLICY IF EXISTS "Authorized users read spatial results" ON spatial_analysis_results;
CREATE POLICY "Authorized users read spatial results" ON spatial_analysis_results FOR SELECT
    USING (public.can_access_analysis(analysis_run_id));
DROP POLICY IF EXISTS "Authorized users read TME assessments" ON tme_assessments;
CREATE POLICY "Authorized users read TME assessments" ON tme_assessments FOR SELECT
    USING (public.can_access_analysis(analysis_run_id));
DROP POLICY IF EXISTS "Authorized users read artifacts" ON analysis_artifacts;
CREATE POLICY "Authorized users read artifacts" ON analysis_artifacts FOR SELECT
    USING (public.can_access_analysis(analysis_run_id));

-- Direct client access to source paths remains limited by session ownership.
DROP POLICY IF EXISTS "Authorized users read image assets" ON image_assets;
CREATE POLICY "Authorized users read image assets" ON image_assets FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM biopsy_sessions bs JOIN patients p ON p.id = bs.patient_id
        JOIN users u ON u.id = auth.uid()
        WHERE bs.id = image_assets.session_id
          AND (p.clinician_id = auth.uid() OR p.patient_user_id = auth.uid() OR u.role = 'admin')
    )
);

DROP POLICY IF EXISTS "Authenticated users read model provenance" ON model_versions;
CREATE POLICY "Authenticated users read model provenance" ON model_versions FOR SELECT
    USING (auth.uid() IS NOT NULL);

COMMIT;

-- The SQL editor should return eight rows, all with table_ready = true.
SELECT expected.table_name, to_regclass('public.' || expected.table_name) IS NOT NULL AS table_ready
FROM unnest(ARRAY[
    'model_versions',
    'image_assets',
    'analysis_runs',
    'cell_instances',
    'tumor_assessments',
    'spatial_analysis_results',
    'tme_assessments',
    'analysis_artifacts'
]) AS expected(table_name)
ORDER BY expected.table_name;
