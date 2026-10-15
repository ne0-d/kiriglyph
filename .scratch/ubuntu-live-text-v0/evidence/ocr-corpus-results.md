# OCR Corpus Results

Generated images: `scripts/acceptance/corpus/generated`
Result JSON: `scripts/acceptance/output/ocr-corpus/ocr-results.json`

## Aggregate

- Cases recognized: 7/7
- Mean CER: 0.005
- Mean line recall/precision: 1.000/1.000
- Geometry failures: 0
- Reading-order errors: 0
- Mean worker OCR time: 427.7 ms

## Per Image

| Image | CER | Recall | Precision | Geometry failures | Reading-order errors | Notes |
|---|---:|---:|---:|---:|---:|---|
| web_article | 0.000 | 1.000 | 1.000 | 0 | 0 | mixed Devanagari/Japanese not covered unless future host fonts are pinned |
| dark_code | 0.035 | 1.000 | 1.000 | 0 | 0 | mixed Devanagari/Japanese not covered unless future host fonts are pinned |
| two_columns | 0.000 | 1.000 | 1.000 | 0 | 0 | mixed Devanagari/Japanese not covered unless future host fonts are pinned |
| ui_buttons | 0.000 | 1.000 | 1.000 | 0 | 0 | mixed Devanagari/Japanese not covered unless future host fonts are pinned |
| low_contrast_small | 0.000 | 1.000 | 1.000 | 0 | 0 | mixed Devanagari/Japanese not covered unless future host fonts are pinned |
| video_subtitle | 0.000 | 1.000 | 1.000 | 0 | 0 | mixed Devanagari/Japanese not covered unless future host fonts are pinned |
| tilted_note | 0.000 | 1.000 | 1.000 | 0 | 0 | tilted text is diagnostic and expected to be harder; mixed Devanagari/Japanese not covered unless future host fonts are pinned |

## Paragraph Grouping

- Dart paragraph corpus test: PASS
- Exact paragraph matches: 4/7
- Command: `cd app && OCR_CORPUS_RESULTS=../scripts/acceptance/output/ocr-corpus/ocr-results.json ../.tools/flutter/bin/flutter test test/tool/paragraph_corpus_eval_test.dart`

| Image | Classification | Expected groups | Actual groups | Interpretation |
|---|---|---|---|---|
| dark_code | split | [0:def crop_display(frame):; 1:return frame.delete_private_co; 2:assert network_calls == 0] | [0:def crop_display(frame):; 1:return frame.delete_private_co]<br>[2:assert network_calls == 0] | Acceptable by design for code-like text: keeping the final assert separate is better than forcing prose paragraph behavior. |
| two_columns | split | [0:Left column first line; 1:Left column second line]<br>[2:Right column first line; 3:Right column second line] | [0:Left column first line]<br>[1:Right column first line]<br>[2:Left column second line]<br>[3:Right column second line] | Follow-up defect/risk: OCR ordered the synthetic columns row-wise, so paragraph grouping cannot recover column paragraphs. |
| ui_buttons | split | [0:Enable instant capture]<br>[1:Copy all; 2:Save PNG; 3:Close] | [0:Enable instant capture]<br>[1:Copy all]<br>[2:Save PNG]<br>[3:Close] | Acceptable by design for toolbar/button clusters: per-control or per-line selection is a better UX than one paragraph. |

## Fonts

- `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`
- `/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf`

## Failures And Limitations

- The corpus is synthetic and non-sensitive; it does not replace manual tests on real web pages, video frames, and image viewers.
- Tilted, low-contrast, and small text cases are diagnostic. This ticket reports failures instead of changing OCR thresholds.
- Paragraph mismatches in `dark_code` and `ui_buttons` are acceptable by design: non-prose layouts should not be forced into prose paragraph selection when per-line or per-control selection is clearer.
- `two_columns` is a real follow-up risk: OCR reading order is row-wise in this fixture, so paragraph grouping cannot reconstruct column paragraphs from the current line order.
- Mixed Devanagari/Japanese is not covered until a suitable font is pinned on the acceptance host.
