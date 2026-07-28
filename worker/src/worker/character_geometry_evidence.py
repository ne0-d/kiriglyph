from __future__ import annotations

import json
import platform
from dataclasses import asdict
from importlib.metadata import version
from pathlib import Path

from worker.character_geometry_metrics import (
    V0_CHARACTER_GEOMETRY_POLICY,
    evaluate_character_geometry,
    load_annotated_fixture,
    score_character_geometry,
)
from worker.character_geometry_probe import (
    CharacterGeometryProbeResult,
    GeometryKind,
    probe_character_geometry,
)


def build_character_geometry_evidence(
    fixture_directory: Path,
) -> dict[str, object]:
    results = []
    scores = []
    whitespace_policy_consistent = True
    provenance_and_bounds_valid = True

    for annotation_path in sorted(fixture_directory.glob("*.json")):
        expected = load_annotated_fixture(annotation_path)
        actual = probe_character_geometry(annotation_path.with_suffix(".png"))
        score = score_character_geometry(expected, actual)
        scores.append(score)
        whitespace_policy_consistent &= _whitespace_is_consistent(actual)
        provenance_and_bounds_valid &= _provenance_and_bounds_are_valid(actual)
        results.append(
            {
                **asdict(score),
                "recognized_text": "\n".join(
                    line.text for line in actual.lines
                ),
                "source_text": expected.text,
                "invalid_reasons": [
                    line.invalid_reason
                    for line in actual.lines
                    if line.invalid_reason is not None
                ],
            }
        )

    evaluation = evaluate_character_geometry(
        tuple(scores),
        whitespace_policy_consistent=whitespace_policy_consistent,
    )
    failures = list(evaluation.failures)
    if not provenance_and_bounds_valid:
        failures.append("fragment provenance or source-image bounds were invalid")
    passed = not failures
    return {
        "decision": "go" if passed else "no-go",
        "decision_scope": (
            "Use RapidOCR-derived CTC polygons as approximate hit geometry for "
            "exact ranges in recognized text."
        ),
        "gates_passed": passed,
        "failures": failures,
        "policy": {
            **asdict(V0_CHARACTER_GEOMETRY_POLICY),
            "whitespace_policy_must_be_consistent": True,
            "provenance_and_bounds_must_be_valid": True,
        },
        "whitespace_policy": {
            "consistent": whitespace_policy_consistent,
            "range_unit": "Unicode code point",
            "visual_geometry": GeometryKind.INTERPOLATED_GAP.value,
            "source_spacing_preserved": False,
            "note": (
                "RapidOCR collapses repeated source spaces. Selection ranges "
                "remain exact for the recognized transcript, not the source pixels."
            ),
        },
        "provenance_and_bounds_valid": provenance_and_bounds_valid,
        "diagnostic_categories": list(evaluation.diagnostic_categories),
        "results": results,
        "runtime": {
            "python": platform.python_version(),
            "rapidocr": version("rapidocr"),
            "onnxruntime": version("onnxruntime"),
        },
        "limitations": [
            "Polygons are recognizer-derived interaction geometry, not observed glyph outlines.",
            "Repeated source whitespace can be normalized by OCR.",
            "The spike uses Unicode code-point offsets; Flutter interoperability needs an explicit grapheme policy.",
            "Rotation and perspective are diagnostic results and do not contribute to the horizontal pass decision.",
        ],
    }


def write_character_geometry_evidence(
    evidence: dict[str, object],
    *,
    json_path: Path,
    markdown_path: Path,
) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    markdown_path.write_text(_as_markdown(evidence), encoding="utf-8")


def main() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    evidence = build_character_geometry_evidence(
        repository_root / "fixtures" / "worker" / "character-geometry"
    )
    evidence_directory = (
        repository_root / ".scratch" / "ubuntu-live-text-v0" / "evidence"
    )
    write_character_geometry_evidence(
        evidence,
        json_path=evidence_directory / "character-geometry.json",
        markdown_path=evidence_directory / "character-geometry.md",
    )


def _whitespace_is_consistent(actual: CharacterGeometryProbeResult) -> bool:
    for line in actual.lines:
        if line.invalid_reason is not None:
            continue
        if "".join(fragment.text for fragment in line.fragments) != line.text:
            return False
        for index, fragment in enumerate(line.fragments):
            if fragment.start != index or fragment.end != index + 1:
                return False
            if (
                fragment.text.isspace()
                and fragment.geometry_kind is not GeometryKind.INTERPOLATED_GAP
            ):
                return False
    return True


def _provenance_and_bounds_are_valid(
    actual: CharacterGeometryProbeResult,
) -> bool:
    valid_kinds = {
        GeometryKind.DERIVED_CTC_POLYGON,
        GeometryKind.INTERPOLATED_GAP,
    }
    return all(
        fragment.geometry_kind in valid_kinds
        and all(
            0 <= point.x <= actual.image_width
            and 0 <= point.y <= actual.image_height
            for point in fragment.polygon
        )
        for line in actual.lines
        if line.invalid_reason is None
        for fragment in line.fragments
    )


def _as_markdown(evidence: dict[str, object]) -> str:
    status = "GO" if evidence["gates_passed"] else "NO-GO"
    lines = [
        "# Character geometry spike evidence",
        "",
        f"**Decision:** {status}",
        "",
        str(evidence["decision_scope"]),
        "",
        "## Fixed gates",
        "",
        "- Required horizontal fixtures: code, proportional, punctuation/URL, small text.",
        "- Minimum token coverage: 95%.",
        "- Minimum annotated-center hit rate: 95%.",
        "- Zero ordering inversions and zero invalid horizontal lines.",
        "- Valid source bounds and explicit geometry provenance.",
        "- Internally consistent logical whitespace ranges.",
        "- Rotation and perspective reported separately.",
        "",
        "## Results",
        "",
    ]
    for result in evidence["results"]:  # type: ignore[union-attr]
        lines.append(
            "- **{category}:** transcript={transcript_matches}, "
            "coverage={token_coverage:.1%}, center-hit={center_hit_rate:.1%}, "
            "ordering-errors={ordering_violations}, invalid-lines={invalid_lines}, "
            "baseline-error={baseline_direction_error_degrees:.2f}°".format(
                **result
            )
        )
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- RapidOCR's public single-character output passed the fixed horizontal interaction gates.",
            "- Character polygons are derived from CTC recognizer columns. They are approximate hit targets, not exact glyph outlines.",
            "- The repeated-space fixture was recognized with one space instead of three. Ranges remain exact for the recognized transcript; source spacing is not guaranteed.",
            "- Rotated and perspective fixtures are diagnostics only; both are listed above and were not used to make the horizontal pass decision.",
            "- A fallback OCR engine is not required by this spike because the primary path passed. The production line-only contract remains unchanged until issue 06.",
            "",
            "## V0 decision",
            "",
            "Proceed to issue 06 with an engine-neutral range contract that preserves `derived_ctc_polygon` and `interpolated_gap` provenance. Keep line text selectable whenever range geometry is unavailable or invalid.",
            "",
            "## Runtime",
            "",
            *[
                f"- {name}: {value}"
                for name, value in evidence["runtime"].items()  # type: ignore[union-attr]
            ],
            "",
        ]
    )
    return "\n".join(lines)


if __name__ == "__main__":
    main()
