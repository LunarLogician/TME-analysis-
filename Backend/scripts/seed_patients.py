"""Seed a repeatable demo patient cohort.

Set SEED_CLINICIAN_ID to the UUID of the clinician who should own the cohort.
The deterministic IDs and upserts make this script safe to run more than once.
"""
import os
import sys
from uuid import UUID, uuid5

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.supabase_client import (
    close_supabase_client,
    create_supabase_service_client,
)


NAMESPACE = UUID("bd7db0e7-0eb2-4af8-938b-07bf7acd9550")
COHORT = (
    ("Jane Doe", "1975-04-12", "Invasive Ductal Carcinoma"),
    ("Mary Smith", "1960-11-23", "Fibroadenoma (Benign)"),
    ("Linda Johnson", "1982-08-05", "Ductal Carcinoma In Situ"),
    ("Patricia Williams", "1955-01-30", "Phyllodes Tumor"),
    ("Elizabeth Brown", "1968-09-14", "Tubular Carcinoma"),
    ("Susan Davis", "1971-02-17", "Mucinous Carcinoma"),
    ("Barbara Miller", "1988-06-09", "Adenosis (Benign)"),
    ("Margaret Wilson", "1959-12-02", "Lobular Carcinoma"),
    ("Dorothy Moore", "1978-03-25", "Tubular Adenoma (Benign)"),
    ("Nancy Taylor", "1964-10-18", "Papillary Carcinoma"),
)


def seed() -> None:
    clinician_id = os.getenv("SEED_CLINICIAN_ID")
    if not clinician_id:
        raise SystemExit("SEED_CLINICIAN_ID is required (use an existing clinician UUID)")

    db = create_supabase_service_client()
    patients = []

    for name, dob, diagnosis in COHORT:
        patient_id = str(uuid5(NAMESPACE, f"patient:{name}"))
        patients.append({
            "id": patient_id,
            "clinician_id": clinician_id,
            "full_name": name,
            "date_of_birth": dob,
            "gender": "Female",
            "diagnosis": diagnosis,
        })

    db.table("patients").upsert(patients).execute()
    print(f"Seeded {len(patients)} patient records")
    close_supabase_client(db)


if __name__ == "__main__":
    seed()
