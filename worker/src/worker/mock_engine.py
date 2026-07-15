from __future__ import annotations

MOCK_LINE_TEXT = "Mock recognized text"
MOCK_CONFIDENCE = 1.0
MOCK_REGION_ID = "line-1"


def mock_line_polygon(width: int, height: int) -> list[list[float]]:
    margin_x = min(max(8, width // 8), max(width - 1, 0))
    margin_y = min(max(8, height // 4), max(height - 1, 0))
    right = min(width, max(margin_x + 1, width - margin_x))
    line_bottom = min(height, margin_y + max(1, height // 2))
    return [
        [margin_x, margin_y],
        [right, margin_y],
        [right, line_bottom],
        [margin_x, line_bottom],
    ]


def build_mock_result(width: int, height: int) -> dict:
    return {
        "image": {"width": width, "height": height},
        "full_text": MOCK_LINE_TEXT,
        "regions": [
            {
                "id": MOCK_REGION_ID,
                "level": "line",
                "text": MOCK_LINE_TEXT,
                "polygon": mock_line_polygon(width, height),
                "confidence": MOCK_CONFIDENCE,
                "reading_order": 0,
            }
        ],
        "timings_ms": {"total": 0},
    }
