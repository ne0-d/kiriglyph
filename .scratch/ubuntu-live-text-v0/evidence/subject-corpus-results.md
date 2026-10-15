# Subject Corpus Results

Command: `worker/.venv/bin/python scripts/acceptance/segmentation-corpus-eval.py`

## Aggregate

- Outcomes: `{'ok': 28, 'suspect_full_image': 1}`
- Median embed/prompt: 1288.3 ms / 253.0 ms
- Peak segmentation RSS: 595.6 MiB
- Sequential bounded sessions: 20
- Mask/runtime cleanup after close: PASS

## Per Fixture

| Fixture | Outcome | Embed ms | Prompt ms | Peak RSS MiB | Mask cleanup | Runtime leftovers |
|---|---|---:|---:|---:|---|---:|
| person | ok | 1225.7 | 253.0 | 595.5 | yes | 0 |
| animal | ok | 1094.3 | 207.4 | 595.4 | yes | 0 |
| product_hole | ok | 1371.5 | 315.7 | 595.5 | yes | 0 |
| overlapping_subjects | ok | 1111.6 | 225.7 | 589.7 | yes | 0 |
| fine_boundaries | ok | 1172.5 | 150.8 | 595.5 | yes | 0 |
| low_contrast | ok | 1192.2 | 243.3 | 595.4 | yes | 0 |
| no_clear_subject | suspect_full_image | 1401.4 | 929.8 | 595.4 | yes | 0 |
| screenshot_photo_window | ok | 1504.6 | 310.3 | 583.5 | yes | 0 |
| screenshot_ui_card | ok | 1246.7 | 195.6 | 583.5 | yes | 0 |

## Boundedness

- Ran 20 sequential spawn/embed/prompt/close sessions on `person`.
- All sessions cleaned mask files: yes.
- All sessions left zero runtime files: yes.

## Limitations

- Fixtures are synthetic and do not represent real screenshots, camera photos, or every edge case.
- This harness measures the real worker protocol and cleanup; it does not judge visual mask quality beyond worker outcomes.
