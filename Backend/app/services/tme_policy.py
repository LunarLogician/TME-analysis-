"""Versioned interpretation policy kept separate from raw measurements."""

from __future__ import annotations

from app.domain.image_metadata import ImageMetadata
from app.domain.quality import QualityAssessment, QualityStatus
from app.domain.spatial import SpatialMeasurements
from app.domain.tme import TMEAssessment, TMEState
from app.domain.tumor import TumorAssessment, TumorStatus


class TMEPolicyV1:
    """Historical 20/60 µm policy with explicit V2 evidence preconditions."""

    policy_version = "tme-policy-v1.1"

    def __init__(self, *, minimum_neoplastic: int = 3, minimum_inflammatory: int = 3):
        self.minimum_neoplastic = int(minimum_neoplastic)
        self.minimum_inflammatory = int(minimum_inflammatory)

    def evaluate(
        self,
        *,
        spatial: SpatialMeasurements | None,
        tumor: TumorAssessment,
        quality: QualityAssessment,
        metadata: ImageMetadata,
    ) -> TMEAssessment:
        measurement_version = spatial.measurement_version if spatial else "spatial-v2.0"
        if quality.status == QualityStatus.FAIL.value:
            return self._result(
                TMEState.NOT_ASSESSABLE,
                measurement_version,
                ["IMAGE_QUALITY_FAILED", *quality.failures],
            )
        if not metadata.scale_trusted:
            return self._result(
                TMEState.NOT_ASSESSABLE,
                measurement_version,
                ["PHYSICAL_SCALE_UNKNOWN"],
            )
        if tumor.status != TumorStatus.PRESENT.value:
            reason = (
                "CLINICIAN_CONFIRMED_NO_TUMOR"
                if tumor.status == TumorStatus.ABSENT.value
                else "TUMOR_NOT_CONFIRMED"
            )
            return self._result(TMEState.NOT_APPLICABLE, measurement_version, [reason])
        if spatial is None:
            return self._result(
                TMEState.INDETERMINATE,
                measurement_version,
                ["SPATIAL_MEASUREMENTS_UNAVAILABLE"],
            )
        if spatial.neo_count_accepted < self.minimum_neoplastic:
            return self._result(
                TMEState.INDETERMINATE,
                measurement_version,
                ["INSUFFICIENT_ACCEPTED_NEOPLASTIC_EVIDENCE"],
            )
        if spatial.immune_count_accepted < self.minimum_inflammatory:
            return self._result(
                TMEState.INDETERMINATE,
                measurement_version,
                ["INSUFFICIENT_ACCEPTED_IMMUNE_EVIDENCE"],
            )
        distance = spatial.neo_to_immune_mean_um
        if distance is None:
            return self._result(
                TMEState.INDETERMINATE,
                measurement_version,
                ["NEAREST_NEIGHBOR_DISTANCE_UNAVAILABLE"],
            )
        if distance < 20.0:
            state = TMEState.HOT
            score = max(0.0, min(1.0, 1.0 - distance / 20.0))
        elif distance <= 60.0:
            state = TMEState.EXCLUDED
            score = max(0.0, min(1.0, (60.0 - distance) / 40.0))
        else:
            state = TMEState.COLD
            score = max(0.0, min(1.0, (distance - 60.0) / 60.0))
        return TMEAssessment(
            state=state,
            policy_version=self.policy_version,
            score=score,
            reason_codes=[],
            input_measurement_version=measurement_version,
        )

    def _result(
        self, state: TMEState, measurement_version: str, reasons: list[str]
    ) -> TMEAssessment:
        return TMEAssessment(
            state=state,
            policy_version=self.policy_version,
            reason_codes=reasons,
            input_measurement_version=measurement_version,
        )
