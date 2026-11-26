"""Human-confirmed tumor context independent of neural cell inference."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from app.domain.tumor import (
    TumorAssessment,
    TumorEvidenceSource,
    TumorRegionMode,
    TumorStatus,
)


class TumorContextService:
    @staticmethod
    def unconfirmed(
        *, confident_neoplastic_count: int = 0, uncertain_neoplastic_count: int = 0
    ) -> TumorAssessment:
        return TumorAssessment(
            status=TumorStatus.INDETERMINATE,
            evidence_source=TumorEvidenceSource.UNCONFIRMED_NUCLEI_ONLY,
            tumor_region_mode=TumorRegionMode.NONE,
            confident_neoplastic_count=confident_neoplastic_count,
            uncertain_neoplastic_count=uncertain_neoplastic_count,
            reason_codes=["TUMOR_NOT_CONFIRMED"],
        )

    @staticmethod
    def clinician_confirmed(
        *,
        present: bool,
        user_id: str,
        region_mode: TumorRegionMode = TumorRegionMode.WHOLE_ROI,
        region_artifact_id: Optional[str] = None,
        confident_neoplastic_count: int = 0,
        uncertain_neoplastic_count: int = 0,
    ) -> TumorAssessment:
        return TumorAssessment(
            status=TumorStatus.PRESENT if present else TumorStatus.ABSENT,
            evidence_source=(
                TumorEvidenceSource.CLINICIAN_CONFIRMED_TUMOR
                if present
                else TumorEvidenceSource.CLINICIAN_CONFIRMED_NO_TUMOR
            ),
            confirmed_by_user_id=user_id,
            confirmed_at=datetime.now(timezone.utc),
            tumor_region_mode=region_mode if present else TumorRegionMode.NONE,
            tumor_region_artifact_id=region_artifact_id if present else None,
            confident_neoplastic_count=confident_neoplastic_count,
            uncertain_neoplastic_count=uncertain_neoplastic_count,
            reason_codes=[] if present else ["CLINICIAN_CONFIRMED_NO_TUMOR"],
        )
