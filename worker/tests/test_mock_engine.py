from __future__ import annotations

import pytest

from worker.mock_engine import mock_line_polygon


@pytest.mark.parametrize(("width", "height"), [(1, 1), (2, 2), (3, 10), (10, 3), (64, 32)])
def test_mock_polygon_stays_in_bounds_and_non_inverted(width: int, height: int):
    polygon = mock_line_polygon(width, height)
    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]

    assert len(polygon) == 4
    assert all(0 <= x <= width for x in xs)
    assert all(0 <= y <= height for y in ys)
    assert polygon[0][0] <= polygon[1][0]
    assert polygon[3][0] <= polygon[2][0]
    assert polygon[0][1] <= polygon[3][1]
    assert polygon[1][1] <= polygon[2][1]
