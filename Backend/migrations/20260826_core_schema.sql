-- ============================================================================
-- TME-Insight Supabase Database Schema
-- Run these SQL commands in your Supabase project's SQL editor
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- Table: users
-- ============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'clinician' CHECK (role IN ('clinician', 'admin', 'patient')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

-- Keep the application profile table synchronized with Supabase Auth. Roles
-- supplied during public signup are constrained to clinician/patient; trusted
-- administrators should be promoted through app_metadata by an operator.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        CASE WHEN NEW.raw_user_meta_data->>'role' = 'patient' THEN 'patient' ELSE 'clinician' END
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- ============================================================================
-- Table: patients
-- ============================================================================
CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinician_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    patient_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    date_of_birth DATE,
    gender TEXT,
    diagnosis TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patients_clinician_id ON patients(clinician_id);
CREATE INDEX idx_patients_patient_user_id ON patients(patient_user_id);
CREATE INDEX idx_patients_created_at ON patients(created_at);

-- ============================================================================
-- Table: biopsy_sessions
-- ============================================================================
CREATE TABLE biopsy_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    session_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    image_url TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'complete', 'failed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_patient_id ON biopsy_sessions(patient_id);
CREATE INDEX idx_sessions_status ON biopsy_sessions(status);
CREATE INDEX idx_sessions_created_at ON biopsy_sessions(created_at);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE biopsy_sessions ENABLE ROW LEVEL SECURITY;

-- Users table policies
CREATE POLICY "Users can view their own profile"
    ON users FOR SELECT
    USING (auth.uid()::TEXT = id::TEXT);

CREATE POLICY "Admins can view all users"
    ON users FOR SELECT
    USING (role = 'admin');

-- Patients table policies
CREATE POLICY "Clinicians can view their own patients"
    ON patients FOR SELECT
    USING (clinician_id = auth.uid()::UUID);

CREATE POLICY "Patients can view their own record"
    ON patients FOR SELECT
    USING (patient_user_id = auth.uid()::UUID);

CREATE POLICY "Clinicians can insert their own patients"
    ON patients FOR INSERT
    WITH CHECK (clinician_id = auth.uid()::UUID);

CREATE POLICY "Clinicians can update their own patients"
    ON patients FOR UPDATE
    USING (clinician_id = auth.uid()::UUID)
    WITH CHECK (clinician_id = auth.uid()::UUID);

CREATE POLICY "Admins can manage all patients"
    ON patients FOR ALL
    USING (TRUE);

-- Biopsy sessions table policies
CREATE POLICY "Clinicians view sessions for own patients"
    ON biopsy_sessions FOR SELECT
    USING (
        patient_id IN (
            SELECT id FROM patients WHERE clinician_id = auth.uid()::UUID
        )
    );

CREATE POLICY "Patients view their own sessions"
    ON biopsy_sessions FOR SELECT
    USING (
        patient_id IN (
            SELECT id FROM patients WHERE patient_user_id = auth.uid()::UUID
        )
    );

CREATE POLICY "Create sessions for own patient"
    ON biopsy_sessions FOR INSERT
    WITH CHECK (
        patient_id IN (
            SELECT id FROM patients WHERE clinician_id = auth.uid()::UUID
        )
    );

CREATE POLICY "Admins can manage all sessions"
    ON biopsy_sessions FOR ALL
    USING (TRUE);

-- ============================================================================
-- Sample Data (Optional - for testing)
-- ============================================================================

-- INSERT INTO users (email, full_name, role) VALUES
--     ('clinician@example.com', 'Dr. Jane Smith', 'clinician'),
--     ('admin@example.com', 'Admin User', 'admin');
--
-- INSERT INTO patients (clinician_id, full_name, date_of_birth, gender, diagnosis) VALUES
--     ((SELECT id FROM users WHERE email = 'clinician@example.com'), 
--      'John Doe', '1980-05-15', 'Male', 'Colon Adenocarcinoma');

-- ============================================================================
-- End of Schema
-- ============================================================================
