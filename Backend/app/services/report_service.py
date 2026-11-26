"""Deterministic V2 report facts with no diagnostic or treatment invention."""

from __future__ import annotations

from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any

from app.domain.analysis import AnalysisOutput


class ClinicalAnalysisContextBuilder:
    def build(self, output: AnalysisOutput, clinical_info: dict[str, Any]) -> dict[str, Any]:
        return {
            "clinical_info": clinical_info,
            "image_quality": output.quality.model_dump(mode="json"),
            "image_scale": output.image_metadata.model_dump(mode="json"),
            "cell_counts": output.cell_counts,
            "accepted_cell_counts": output.accepted_cell_counts,
            "uncertain_cell_counts": output.uncertain_cell_counts,
            "tumor_context": output.tumor_assessment.model_dump(mode="json"),
            "spatial": (
                output.spatial_measurements.model_dump(mode="json")
                if output.spatial_measurements
                else None
            ),
            "tme": output.tme_assessment.model_dump(mode="json"),
            "model": output.model_metadata.model_dump(mode="json"),
            "warnings": output.warnings,
        }


class V2ReportService:
    def __init__(self, storage_root: str | Path):
        self.storage_root = Path(storage_root)
        self.context_builder = ClinicalAnalysisContextBuilder()

    def generate(
        self,
        *,
        output: AnalysisOutput,
        clinical_info: dict[str, Any],
    ) -> Path:
        context = self.context_builder.build(output, clinical_info)
        pdf = self._render(context, output.analysis_run_id)
        destination = self.storage_root / "analysis-artifacts" / output.analysis_run_id
        destination.mkdir(parents=True, exist_ok=True)
        report_path = destination / "report.pdf"
        report_path.write_bytes(pdf)
        return report_path

    @staticmethod
    def _render(context: dict[str, Any], analysis_run_id: str) -> bytes:
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import letter
        from reportlab.lib.styles import getSampleStyleSheet
        from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

        buffer = BytesIO()
        document = SimpleDocTemplate(buffer, pagesize=letter)
        styles = getSampleStyleSheet()
        story = [
            Paragraph("TME-Insight V2 Structured Analysis Report", styles["Title"]),
            Paragraph(f"Analysis run: {analysis_run_id}", styles["Normal"]),
            Paragraph(
                f"Generated: {datetime.now(timezone.utc).isoformat()}", styles["Normal"]
            ),
            Spacer(1, 12),
        ]

        def section(title: str, rows: list[tuple[str, Any]]) -> None:
            story.append(Paragraph(title, styles["Heading2"]))
            table = Table([[key, "Unavailable" if value is None else str(value)] for key, value in rows], colWidths=[180, 330])
            table.setStyle(
                TableStyle(
                    [
                        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
                        ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
                        ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ]
                )
            )
            story.extend([table, Spacer(1, 10)])

        clinical = context["clinical_info"]
        section(
            "1. Clinical information supplied by clinician",
            [
                ("Patient", clinical.get("full_name", "Not supplied")),
                ("Diagnosis/history", clinical.get("diagnosis", "Not supplied")),
            ],
        )
        image = context["image_scale"]
        quality = context["image_quality"]
        section(
            "2. Image quality and physical scale",
            [
                ("QC status", quality["status"]),
                ("Tissue fraction", quality["tissue_fraction"]),
                ("Scale trusted", image["scale_trusted"]),
                ("Scale source", image["scale_source"]),
                ("MPP X / Y", f"{image.get('source_mpp_x')} / {image.get('source_mpp_y')}"),
            ],
        )
        section(
            "3. AI nuclei analysis",
            [(name, count) for name, count in context["cell_counts"].items()],
        )
        section(
            "4. Accepted and uncertain cell counts",
            [
                (f"Accepted {name}", count)
                for name, count in context["accepted_cell_counts"].items()
            ]
            + [
                (f"Uncertain {name}", count)
                for name, count in context["uncertain_cell_counts"].items()
            ],
        )
        tumor = context["tumor_context"]
        section(
            "5. Tumor-context provenance",
            [
                ("Status", tumor["status"]),
                ("Evidence source", tumor["evidence_source"]),
                ("Confirmed by", tumor.get("confirmed_by_user_id")),
                ("Confirmed at", tumor.get("confirmed_at")),
                ("Region mode", tumor.get("tumor_region_mode")),
            ],
        )
        spatial = context["spatial"]
        section(
            "6. Spatial TME measurements",
            [(key, value) for key, value in spatial.items()]
            if spatial
            else [("Status", "Unavailable")],
        )
        tme = context["tme"]
        section(
            "7. TME interpretation",
            [
                ("State", tme["state"]),
                ("Policy version", tme["policy_version"]),
                ("Score", tme.get("score")),
                ("Reason codes", ", ".join(tme.get("reason_codes", []))),
            ],
        )
        limitations = list(context["warnings"])
        limitations.append(
            "This nuclei/TME analysis is pathologist-assisted decision support and is not a primary diagnosis or treatment-response prediction."
        )
        section(
            "8. Limitations and uncertainty",
            [("Limitation", limitation) for limitation in limitations],
        )
        model = context["model"]
        section(
            "9. Model and analysis provenance",
            [
                ("Model", f"{model['model_name']} {model['model_version']}"),
                ("Architecture", model["architecture"]),
                ("Checkpoint SHA-256", model["checkpoint_sha256"]),
            ],
        )
        document.build(story)
        return buffer.getvalue()
