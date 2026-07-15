# Local OCR engine research for Ubuntu Live Text

Target: Ubuntu 24.04 LTS or newer, x86-64 CPU first, fully offline at runtime  
Ticket: [02-local-ocr-engine](../issues/02-local-ocr-engine.md)

## Decision

Do **not** select a winner from upstream benchmark numbers. Run a pinned,
project-owned feasibility bake-off with this short list:

1. **Tesseract 5.5.3 + `tessdata_fast/eng`** as the compact, distro-friendly,
   Python-free baseline.
2. **PaddleOCR 3.7.0 + PP-OCRv6 small detection and recognition** using the
   supported Python pipeline and CPU `paddle_static` runtime.
3. **RapidOCR 3.10.0 + ONNX Runtime CPU + PP-OCRv6 small detection and
   recognition** as the lighter maintained ONNX/Python path.

Also run a bounded **direct ONNX Runtime C/C++ embedding spike** with the same
PP-OCRv6 ONNX models. It is a deployment feasibility check, not a fourth
accuracy candidate. PP-OCRv6 tiny is an optional low-footprint profile of
candidates 2 and 3, not another engine.

The short list deliberately represents three different risks:

- Tesseract has the cleanest native integration and packaging story, but its
  layout analysis plus line recognizer is not a modern arbitrary-scene text
  detector and exposes only rectangular word/line geometry.
- PP-OCRv6 is explicitly designed and trained for diverse screenshot, scene,
  rotated, artistic, and industrial text, but its published accuracy is
  vendor-measured and the official Python deployment is comparatively large.
- RapidOCR makes PP-OCR models practical through ONNX Runtime and is actively
  maintained in Python, but its current native C++ sibling is unmaintained; a
  Python-free product would own preprocessing, DB postprocessing, crop
  rectification, CTC decoding, word-box reconstruction, and reading order.

There is no evidence-backed winner until all three run on the same Ubuntu
machine and the same held-out screenshot/scene corpus.

## Why these candidates

All three engine projects are actively released. Tesseract 5.5.3 was released
2026-07-24, PaddleOCR 3.7.0 on 2026-06-11, and RapidOCR 3.10.0 on 2026-10-08.
Microsoft released ONNX Runtime 1.31.0 on 2026-10-09.[Tesseract release][t-release]
[PaddleOCR release][p-release] [RapidOCR release][r-release]
[ONNX Runtime releases][ort-releases]

The maintained ONNX option is specifically **PP-OCRv6 models on ONNX Runtime**,
using RapidOCR as the maintained Python reference implementation. PaddleOCR
3.7 can itself load ONNX models, so that is a runtime variant of the Paddle
candidate rather than an independent OCR family.[Paddle inference engines][p-engines]
The older `RapidAI/RapidOcrOnnx` C++ application is not a production candidate:
its latest stable release was 1.2.2 in 2023, 1.2.3 was a January 2024
pre-release, its maintainer stated in 2025 that it was no longer maintained,
and PP-OCRv5 support was still an open request in 2026.
[RapidOcrOnnx releases][ro-release] [RapidOcrOnnx maintenance][ro-maint]
[RapidOcrOnnx v5 request][ro-v5]

EasyOCR, docTR, MMOCR, and transformer recognizers were not added to the short
list. Their maintained reference stacks are primarily Python/PyTorch or
TensorFlow, they do not improve the native/offline integration story, and some
are recognizers rather than complete detector + recognizer + spatial-output
pipelines. Adding them now would increase the bake-off surface without closing
one of the identified gaps.

## Capability comparison

| Requirement | Tesseract 5.5.3 | PaddleOCR 3.7 / PP-OCRv6 small | RapidOCR 3.10.0 / PP-OCRv6 small + ORT |
|---|---|---|---|
| Detection + recognition | Integrated page segmentation and LSTM line recognition | Separate learned text detector, rectified line crops, learned recognizer | Same detector/recognizer family with RapidOCR preprocessing and postprocessing |
| Line geometry | Axis-aligned rectangle plus baseline | Four-point quadrilateral | Four-point quadrilateral |
| Word geometry | Native axis-aligned word rectangles | Optional recognition-derived word/character locations; validate fidelity | Optional recognition-derived English word boxes/character boxes; validate fidelity |
| Confidence | Word and iterator-level score, 0–100 | Detection and recognition scores | Combined OCR exposes line/word recognition scores; detector scores require detector-only/internal output |
| Default reading order | Tesseract iterator order; sparse mode explicitly has no particular order | Top-to-bottom/left-to-right geometric sort | Top-to-bottom/left-to-right geometric sort |
| Cardinal rotation | Whole-page OSD can report 0/90/180/270 and deskew | Optional document orientation model handles 0/90/180/270 | Bundled line classifier handles 0/180; no equivalent full-page 90/270 stage |
| Arbitrary rotated/perspective lines | Limited; usually needs external deskew/detection | Detector returns rotated quads and crops are rectified | Same model capability and crop approach |
| Multilingual extension | 100+ languages and 35+ scripts, normally separate data files | Small/medium unified model covers 50 languages: four core languages plus Latin-script set; v5 models cover additional scripts | Same v6 coverage; older routed models cover additional scripts |
| CPU | Yes; current upstream is effectively CPU-only | Paddle Inference, ONNX Runtime, or OpenVINO | ONNX Runtime default; OpenVINO, Paddle, Torch, MNN also supported |
| Optional GPU | No current supported GPU path | NVIDIA through Paddle/CUDA or compatible TensorRT/ORT configurations | TensorRT and other configured backends; CPU remains the recommended default |
| Python-free | First-class C/C++ and C API | Official C++ path exists, but PP-OCRv6 needs a release-specific spike | Model/runtime are embeddable; the maintained RapidOCR wrapper is Python |
| Redistribution | Permissive engine/model licenses; small distro packages | Permissive code/model licenses, larger runtime and third-party notice set | Permissive code/runtime/model licenses with model attribution and hashes; transitive notices still need audit |

The score semantics differ. At word level Tesseract maps its internal certainty
as `clip(100 + 5 × certainty)`; at line and higher levels it first averages
word certainties. Paddle/Rapid DB detection scores are means over the detector
probability map inside a candidate region, while CTC recognition scores are
means of retained maximum token probabilities after blank and repeat removal.
RapidOCR's combined result object keeps recognition scores but not its
detector-stage scores.[Tesseract confidence source][t-confidence]
[Paddle DB score source][p-det-score] [Paddle CTC score source][p-rec-score]
[RapidOCR combined output source][r-main]

None is promised as a calibrated probability, and a score of 0.8 or 80 does
not have the same error likelihood across engines, image classes, or model
versions. Thresholds must be calibrated on project data; raw scores must not
be compared as if they shared a scale.

## Tesseract

### Spatial output and reading order

`ResultIterator` can return text, confidence, and a bounding box at word or
text-line level. `PageIterator` also exposes a line baseline. These word and
line boxes are bounding **rectangles**; `BlockPolygon()` is available only at
block level, so Tesseract cannot directly provide rotated word/line
quadrilaterals.[Tesseract API example][t-api] [Tesseract PageIterator][t-page]

TSV is convenient for a prototype, but its documented confidence is populated
on word rows while line rows show `-1`; the native iterator is the better
integration API when line confidence or baseline data is needed.[Tesseract TSV][t-tsv]
The result iterator accounts for logical direction inside bidirectional text,
but that does not create semantic document ordering. Page segmentation mode 11
is attractive for scattered UI text and is explicitly documented as finding
sparse text “in no particular order.” The bake-off must test both normal
automatic layout and sparse mode instead of assuming one is correct for all
screens.[Tesseract iterator][t-order] [Tesseract page segmentation][t-psm]

### Orientation and recognition fit

The OSD API reports script, cardinal orientation, confidence, and a deskew
angle for the analyzed layout.[Tesseract API example][t-api] It is a
whole-image/layout operation, not a per-line arbitrary-scene orientation
classifier. Sparse text, short labels, and mixed orientations are therefore
mandatory tests. For an already detected single line, Tesseract's own
documentation recommends raw-line mode, which also makes Tesseract useful as
a recognizer behind a separate detector, but that hybrid would be a new
candidate with its own engineering cost.[Tesseract LSTM overview][t-lstm]

Tesseract supports UTF-8, more than 100 languages, and official data for more
than 35 scripts. Additional languages are loaded as data files and can be
combined, with an explicit speed/accuracy cost when more languages are active.
[Tesseract README][t-readme]

### Runtime, embedding, and concurrency

Tesseract exposes first-party C++ and C APIs and is the least risky option for
C/C++, Rust FFI, or a Dart/Flutter native plugin. Community Rust and Dart
wrappers exist, but a product requiring complete spatial output should audit
their APIs rather than assume they expose `ResultIterator`, baselines, OSD, and
per-level confidence. Calling the C API directly through a narrow project-owned
shim remains straightforward.

Use one `TessBaseAPI` instance per worker. Upstream documents multiple
instances as safe in parallel, with the exception that some `classify` and
`textord` control parameters remain global; sharing one mutable instance or
changing those global parameters concurrently is unsafe.[Tesseract thread/API notes][t-thread]
Current Tesseract has no supported GPU path: OpenCL was experimental, did not
accelerate the LSTM engine, and was removed in the 5.4 line.[Tesseract OpenCL removal][t-opencl]

### Footprint, models, and license

Upstream recommends `tessdata_fast` for the speed/accuracy trade-off and calls
`tessdata_best` slower but slightly more accurate. Its own benchmark compares
Tesseract builds and model sets, not scene-text systems, and therefore supports
testing `fast` first but not a cross-engine accuracy claim.[Tesseract data files][t-data]
[Tesseract benchmark][t-benchmark]

Ubuntu 24.04 packages Tesseract 5.3.4, not current 5.5.3. On amd64 its declared
installed sizes are about 1.1 MB for the CLI, 3.2 MB for `libtesseract5`, 4.0 MB
for English data, and 10.3 MB for OSD, excluding shared dependency closure.
That is roughly 18.6 MB for those four packages and is an indicative packaging
baseline, not the size of an upstream 5.5.3 bundle.[Ubuntu Tesseract][t-ubuntu]
[Ubuntu libtesseract][t-ubuntu-lib] [Ubuntu English data][t-ubuntu-eng]
[Ubuntu OSD data][t-ubuntu-osd] The bake-off should use 5.5.3 because its
release includes model-deserialization memory-safety fixes, while separately
recording whether the product will vendor it or accept the older LTS package.

The engine and official model repositories use Apache-2.0; Leptonica uses a
two-clause BSD-style license. Redistribution is practical if license,
copyright, NOTICE, model source/version, and modifications are retained.
[Tesseract license][t-license] [Tessdata license][tessdata-license]
[Leptonica license][lept-license]

## PaddleOCR and PP-OCRv6

### Spatial output and reading order

The general OCR result exposes:

- detection quadrilaterals (`dt_polys`) and detection scores (`dt_scores`);
- recognized text and recognition scores;
- confidence-filtered quadrilaterals (`rec_polys`);
- axis-aligned convenience rectangles (`rec_boxes`); and
- optional word-level locations through `return_word_box`.

The documented quadrilateral shape is four points by two coordinates.
[Paddle OCR output][p-output] PP-OCRv6's detector is described as supporting
printed, handwritten, rotated, curved, and artistic text, but the general OCR
pipeline still returns a four-point approximation. Curved text fidelity must
be measured rather than inferred from the model's scenario label.
[PP-OCRv6 detection card][p-det-card]

Word/character positions are reconstructed from recognizer alignment inside a
detected line, not independently detected word polygons. That is suitable for
an overlay only if polygon IoU and word-splitting tests pass for English
punctuation, code, URLs, mixed font sizes, and perspective text.
[Paddle word locations][p-word]

The default OCR system sorts boxes by the first point's y coordinate and then
x, with a ten-pixel same-line adjustment. That is a geometric heuristic, not
semantic reading order for columns, sidebars, menus, or dashboards.
[Paddle sorting source][p-sort] Paddle has a separate PP-DocLayoutV2 model with
a learned pointer network for document-element order, but adding that large,
document-oriented subsystem should be a separate decision after the lightweight
OCR path is measured.[Paddle layout ordering][p-layout]

### Orientation and languages

The optional document orientation model classifies 0/90/180/270; the text-line
orientation classifier handles only 0/180. Rotated detector boxes are rectified
before recognition, so arbitrary line angles can work without being explicit
orientation classes, but full-frame rotation, sparse labels, and mixed-angle
content still need local tests.[Paddle document orientation][p-doc-orient]
[Paddle line orientation][p-line-orient]

PP-OCRv6 small and medium use one recognition model for 50 languages:
Simplified Chinese, Traditional Chinese, English, Japanese, and 46
Latin-script languages. Tiny omits Japanese. Arabic, Cyrillic, Indic, and
other scripts require an older/script-specific recognition model and another
artifact, configuration, and test lane.[PP-OCRv6 languages][p-v6]

### Runtime, embedding, and concurrency

The Python pipeline can run Paddle static/dynamic inference or ONNX Runtime
explicitly. Its high-performance mode can select Paddle Inference, OpenVINO,
ONNX Runtime, or TensorRT; exact support depends on OS, architecture, CUDA,
cuDNN, and TensorRT versions.[Paddle inference engines][p-engines]
[Paddle high-performance inference][p-hpi] The CPU bake-off should pin one
backend per result instead of allowing automatic selection to change between
machines.

There is an official Linux C++ pipeline using Paddle Inference and OpenCV for
CPU or NVIDIA GPU.[Paddle C++ deployment][p-cpp] It is not yet a low-risk
PP-OCRv6 embedding choice: the current official example still names PP-OCRv5
models. A closed 3.7 issue reports a Windows PP-OCRv6 detector startup crash
because the C++ predictor expected a resize key absent from the model
configuration. Users reported guarding that key and source-building Paddle
3.4 as workarounds, but the issue links no upstream fix or official v6 C++
example. It has not been reproduced on Ubuntu; this is evidence for a required
release-specific spike, not proof of Linux failure.
[Paddle C++ deployment][p-cpp] [Paddle v6 C++ issue][p-cpp-issue]

For concurrency, Paddle documents cloning a predictor or using one
`PredictorPool` predictor per worker. Do not invoke one mutable predictor from
several workers.[Paddle PredictorPool][p-thread] Rust and Dart have no
first-party OCR binding; both need a C-compatible shim over the C++ pipeline or
a direct runtime integration.

### Footprint, models, and license

Official model storage sizes are:

- PP-OCRv6 tiny: 1.9 MB detector + 4.4 MB recognizer;
- PP-OCRv6 small: 9.6 MB detector + 20.4 MB recognizer;
- optional document orientation: 7 MB;
- optional text-line orientation: 0.96 MB or 6.5 MB, depending on classifier.

The official small ONNX artifacts are about 9.88 MB and 21.2 MB.
[Paddle OCR models][p-output] [Paddle document orientation][p-doc-orient]
[Paddle line orientation][p-line-orient] [PP-OCRv6 detection card][p-det-card]
[PP-OCRv6 recognition card][p-rec-card]

The runtime dominates the model size. Paddle documents a May 2025 Linux
x86-64/Python 3.10 environment in which the required dependency set was 738 MB
installed. That is not a current package-closure measurement, but it establishes
that the official Python stack is in a different footprint class from
Tesseract or a direct ONNX Runtime build.[Paddle dependency footprint][p-footprint]
The C++ inference closure must be measured separately; upstream does not
publish a stripped, product-equivalent bundle size.

PaddleOCR, PaddlePaddle, and the official PP-OCRv6 ONNX model cards use
Apache-2.0.[PaddleOCR license][p-license] [Paddle license][paddle-license]
[PP-OCRv6 detection card][p-det-card] [PP-OCRv6 recognition card][p-rec-card]
The core license is permissive, but redistribution must retain the applicable
notices for bundled third-party inference libraries. NVIDIA CUDA, cuDNN, and
TensorRT add separate proprietary distribution terms, which is another reason
to keep the release gate CPU-first.

## RapidOCR and direct ONNX Runtime

### What is maintained

RapidOCR 3.9 made PP-OCRv6 small detection and recognition its defaults.
RapidOCR 3.10 centralizes multilingual model routing and license metadata and
records model URLs and SHA-256 values.[RapidOCR 3.9 notes][r-39]
[RapidOCR release][r-release] [RapidOCR model registry][r-models] Version
3.10.0 supports the maintained Python pipeline and multiple inference
backends. It does **not** make the old RapidOcrOnnx C++ repository current.

RapidOCR returns line quadrilaterals shaped `(N, 4, 2)`, corresponding text,
line recognition scores, stage timings, and optional word results. Its detector
also calculates DB scores, but the combined OCR result does not carry them.
[RapidOCR output][r-output] [RapidOCR combined output source][r-main] For
English/numeric lines, current word boxes are derived by grouping recognizer
columns into words and mapping rectangles back to the detected line. They are
useful but still derived geometry that needs local IoU validation.
[RapidOCR word-box source][r-word]

Two open 3.10 defects are directly relevant to an overlay. Grouped English
words can receive the wrong per-word confidence because line character
probabilities are zipped to words instead of averaged per word; word boxes are
also mirrored after the 0/180 classifier rotates an upside-down crop.
[RapidOCR word-score defect][r-word-score]
[RapidOCR 180-degree word-box defect][r-word-rotation]

Reading order is again a y-then-x geometric sort with fixed y grouping, not
layout understanding.[RapidOCR sorting source][r-sort] PP-OCRv6 has no
dedicated classifier in RapidOCR; the project reuses an older 0/180
text-line classifier.[RapidOCR v6 integration][r-v6-cls] A product needing
90/270 full-screen correction must add and benchmark a preprocessing stage or
another orientation model.

### Runtime and native embedding

ONNX Runtime is a credible maintained native runtime with first-party C and
C++ APIs. Its C API can create sessions from a file or memory and select
execution providers. The project lists Rust as a **community** API and does not
list Dart, so Rust should pin and audit the community `ort` crate while Dart
needs FFI to a C ABI or a native platform plugin.[ONNX Runtime APIs][ort-api]
[ONNX Runtime C API][ort-c]

ONNX Runtime asks each execution provider whether concurrent `Run()` calls on
one session are supported and serializes providers that say no. Concurrency is
therefore provider-dependent, not a blanket session guarantee. That contract
does not make the RapidOCR Python object thread-safe: RapidOCR owns mutable
per-call configuration, preprocessing, postprocessing, and lazy model
construction.[ONNX Runtime provider concurrency][ort-thread]
[RapidOCR combined output source][r-main] RapidOCR 3.10 added locks because
concurrent first calls could construct models more than once; the locks cover
initialization, not a published whole-pipeline concurrency contract.
[RapidOCR release][r-release] [RapidOCR lazy-load fix][r-lock]
Use one warmed RapidOCR instance per worker/process for the bake-off and test
1/2/4-worker stability before considering shared instances.

The direct C/C++ spike must reproduce all of the following before it is called
viable:

1. exact resize, normalization, tensor layout, and color conversion;
2. DB detector thresholding, contour extraction, unclipping, quad ordering,
   and small-box filtering;
3. perspective crop and vertical-line handling;
4. recognizer resizing/batching and CTC decoding with the exact dictionary;
5. 0/180 classification or a documented replacement;
6. confidence outputs, word grouping, and coordinate mapping; and
7. deterministic reading-order logic.

Loading two ONNX files successfully is not an OCR integration proof. The spike
passes only when its output matches RapidOCR on a golden fixture set within
defined text, score, and coordinate tolerances.

### Footprint and license

The RapidOCR 3.10.0 wheel is 27.3 MB compressed and already contains its
default detector, recognizer, and classifier models. ONNX Runtime 1.31.0's
native CPU Linux x64 archive is 10.9 MB compressed; the official PP-OCRv6
small detector/recognizer pair is about 31 MB when vendored separately.
Python, NumPy, OpenCV, Shapely, GEOS, and the remaining wrapper dependencies
are additional; actual installed and AppImage/Flatpak closures must be
measured.[RapidOCR PyPI metadata][r-pypi] [RapidOCR model licenses][r-model-license]
[ONNX Runtime release][ort-releases]

RapidOCR code and its documented model artifacts are Apache-2.0; ONNX Runtime
is MIT and publishes third-party notices.[RapidOCR license][r-license]
[RapidOCR model licenses][r-model-license] [ONNX Runtime license][ort-license]
[ONNX Runtime notices][ort-notices] RapidOCR 3.10.0's package metadata lists
both `LICENSE` and `MODEL_LICENSES.md`; the model notice identifies the three
default ONNX artifacts, upstream ownership, Apache-2.0 terms, and exact hashes.
That closes the prior model-attribution gap, but the release artifact and
complete dependency notices still need an SBOM audit.
[RapidOCR PyPI metadata][r-pypi] [RapidOCR model licenses][r-model-license]

The Python closure also contains non-Apache components. RapidOCR 3.10 depends
on `opencv-python-headless`, avoiding the non-headless wheel's Qt payload, but
OpenCV wheels include LGPL-2.1 FFmpeg and Shapely wheels can bundle LGPL GEOS.
These are usable, but their notices and dynamic-library obligations belong in
the package/SBOM; system libraries may reduce closure size.
[RapidOCR PyPI metadata][r-pypi] [OpenCV Python licenses][opencv-license]
[Shapely and GEOS licenses][shapely-license]

## Published evidence is not a head-to-head benchmark

The available numbers answer narrower questions:

- Tesseract's official benchmark compares Tesseract versions and its
  `fast`/`best` model sets. It does not evaluate learned scene-text detection,
  screenshot word geometry, or the other engines.[Tesseract benchmark][t-benchmark]
- Paddle reports PP-OCRv6 small detector Hmean 84.1 and weighted recognition
  accuracy 81.3, including a separate “Screen” recognition category. The
  documentation labels these as an internal multi-scenario evaluation and
  warns that even PP-OCRv6 and older Paddle model metrics use different sets.
  These numbers justify testing the model; they cannot rank it against
  Tesseract.[Paddle OCR models][p-output] [PP-OCRv6 recognition card][p-rec-card]
- Paddle publishes end-to-end latency on A100/V100, Intel Xeon 8350C, and
  Apple M4 across several backends. This is evidence that the model runs on
  CPU and that backend choice matters, not a latency prediction for the target
  machine.[PP-OCRv6 performance][p-v6]
- RapidOCR publishes conversion/backend checks intended to show parity of
  converted models, including TensorRT versus ONNX Runtime. Those checks
  validate conversion and runtime behavior, not superiority over another OCR
  family.[RapidOCR TensorRT check][r-trt]

None of those tests use this project's exact Ubuntu hardware, capture sizes,
small desktop fonts, annotation policy, preprocessing, threading, cold-start
definition, or package build. Reporting the numbers in one league table would
be misleading.

## Reproducible feasibility bake-off

### 1. Freeze artifacts

Create a manifest before testing:

- Ubuntu version, kernel, CPU model/microcode, RAM, CPU governor, compiler,
  Python, and glibc;
- exact source tags/commits, package versions, build flags, and SHA-256 hashes;
- exact model files, dictionaries, configuration, and licenses;
- inference backend, execution providers, precision, graph optimization, and
  intra/inter-op thread settings; and
- a complete installed-file closure and SBOM.

Vendor every model before the test, disable networking, use an empty model
cache, and fail on attempted download. RapidOCR's visualization helper can
download a font on first use, while model-based pipelines commonly download
defaults; neither is acceptable in the offline run.[RapidOCR output][r-output]

Initial pinned configurations:

- **Tesseract:** 5.5.3, pinned `tessdata_fast/eng`, LSTM engine; compare PSM 3
  and PSM 11 on the calibration split, then freeze one. Use OSD only in the
  declared rotation profile.
- **Paddle:** `paddleocr==3.7.0`, PP-OCRv6 small detector/recognizer,
  `paddle_static` CPU, document unwarping off. Record orientation modules as a
  separate on/off profile.
- **Rapid:** `rapidocr==3.10.0`, PP-OCRv6 small detector/recognizer,
  `onnxruntime==1.31.0` CPU. Because ORT was released one day after RapidOCR,
  require a golden-fixture smoke test; if it fails, pin the newest compatible
  ORT that passes and record the deviation rather than leaving it unconstrained.
- **Size sensitivity:** repeat Paddle and Rapid with PP-OCRv6 tiny only if small
  misses the latency or package budget.

### 2. Build the corpus

Use a project-owned corpus as the primary decision set:

- about 160 Ubuntu screenshots: browser, terminal, editor, menus, dialogs,
  settings, light/dark themes, anti-aliasing, 100/125/150/200% scaling, and
  fonts from roughly 8–24 physical pixels;
- about 100 scene/display images: signs, labels, monitors, phones, glare,
  blur, low contrast, compression, perspective, curved text, and clutter; and
- about 40 rotation stress images: 90/180/270 full-frame rotation plus
  per-line ±5/15/30/45 degrees and mixed orientations.

Annotate line and word transcripts, four-point word polygons, line grouping,
and intended reading order. Mark illegible and intentionally ignored text
explicitly. Use a calibration split for page mode, thresholds, resize limits,
and orientation choices, then lock configuration before evaluating the held-out
split.

Add ICDAR 2015 incidental scene text as a public sanity set, not as a substitute
for Ubuntu screenshots. Its official protocol uses word quadrilaterals,
IoU-based localization, and exact case-insensitive transcription for
end-to-end matching.[ICDAR 2015 protocol][icdar]

### 3. Normalize outputs

Map each engine into one versioned schema:

`line polygon, transcript, detection score?, recognition score?, ordered word
items, orientation metadata, reading index, stage timings`.

Evaluate default line geometry for all engines. Convert Tesseract rectangles
to four-point rectangular polygons without implying rotation precision. Score
word geometry separately and label Paddle/Rapid word polygons as derived.
Do not penalize an engine for lacking a detection score by substituting its
recognition score.

### 4. Measure quality

Report by screenshot, scene, and rotation strata:

- line and word detection precision/recall/Hmean at polygon IoU 0.5 and 0.75;
- matched-line and end-to-end character error rate, word error rate, and exact
  match;
- polygon IoU, missed tiny-text rate, and split/merge errors;
- reading-order pairwise error or normalized Kendall distance;
- precision/recall curves against each engine's own confidence;
- reliability diagrams and calibration error for “transcript is correct”;
- 0/90/180/270 and arbitrary-angle success separately; and
- qualitative failure buckets with saved, non-sensitive fixtures.

Use no vocabulary correction in the core comparison. If a later product layer
adds a spell-checker, language model, or UI-context recovery, measure that as a
separate stage.

### 5. Measure CPU and packaging behavior

For fixed region sizes and full-HD/HiDPI screenshots, record:

- process cold start, first OCR, and warm p50/p95/p99 latency;
- detection, classification, recognition, and postprocessing time separately;
- CPU time, wall time, peak RSS, idle RSS, and model-load memory;
- one request and 1/2/4 concurrent workers;
- one-thread mode and a fixed total-core-budget mode to expose oversubscription;
- compressed artifact size and installed dependency closure; and
- 1000 repeated jobs, cancellation, malformed images, model corruption,
  worker restart, and concurrent first-use behavior.

Decode the image once and exclude screen capture from OCR timing. Give every
candidate the same pixels. Record any engine-specific resize or preprocessing
as part of the candidate; also run one shared-preprocessing profile if tiny
screen fonts require upscaling.

### 6. Production gates

Reject a stack before ranking if it:

- downloads code, models, fonts, or dictionaries at runtime;
- cannot return stable line geometry and usable English word geometry;
- cannot survive repeated and concurrent runs with the chosen worker model;
- lacks a complete redistributable license/notice/model-provenance bundle;
- cannot be pinned and rebuilt for the intended package format; or
- has no credible path to the project's required embedding language.

Among candidates that pass, choose from the measured accuracy/latency/memory
Pareto frontier. Accuracy on held-out small screenshot text should be the
primary criterion; package size and native simplicity should break a close
result. Set absolute latency, RAM, and quality thresholds with the interaction
ticket before unblinding final results.

## Blockers and unresolved decisions

1. **Python-free requirement:** Tesseract is ready; current PP-OCRv6 options
   need either a successful Paddle C++ 3.7 spike or a project-owned direct ORT
   pipeline. RapidOCR's maintained implementation is not a native SDK.
2. **Reading order:** none of the lightweight defaults provides trustworthy
   semantic order for arbitrary multi-column screens. The product likely needs
   a geometry/layout layer independent of OCR.
3. **Word polygons:** Paddle/Rapid word locations are recognizer-derived and
   Tesseract's are axis-aligned. Exact clickable-word quality is unproven;
   RapidOCR 3.10 also has open word-confidence and 180-degree mapping defects.
4. **Confidence:** all thresholds need local calibration.
5. **Rotation:** 90/270 and mixed-angle behavior is not equivalent across
   candidates; a common orientation preprocessor may be required.
6. **Redistribution closure:** RapidOCR/Paddle Python dependencies, Paddle's
   native third-party bundle, and wheels containing LGPL components need an
   artifact-level audit. RapidOCR 3.10's model notice improves provenance but
   does not replace a full SBOM.
7. **Target budgets:** no ticket currently supplies a hard p95 latency, RAM,
   installed-size, or minimum accuracy gate, so a measured Pareto result cannot
   yet be converted into an automatic winner.

## Recommendation after research

Proceed with the three-candidate CPU bake-off and the direct-ORT embedding
spike. Do not eliminate Tesseract before testing: its geometry is weaker, but
its native API, package size, language packs, and redistribution path make it
the important baseline. Do not promote PP-OCRv6 from promising to selected
based on vendor metrics. If the product must be Python-free, treat native
PP-OCRv6 integration as a blocking feasibility gate before spending time on
fine-grained accuracy tuning.

## Primary sources

[t-release]: https://github.com/tesseract-ocr/tesseract/releases/tag/5.5.3
[t-readme]: https://github.com/tesseract-ocr/tesseract/blob/main/README.md
[t-api]: https://tesseract-ocr.github.io/tessdoc/APIExample.html
[t-page]: https://tesseract-ocr.github.io/tessapi/5.x/a02486.html
[t-tsv]: https://tesseract-ocr.github.io/tessdoc/Command-Line-Usage.html
[t-order]: https://tesseract-ocr.github.io/tessapi/5.x/a02534.html
[t-psm]: https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html
[t-lstm]: https://tesseract-ocr.github.io/tessdoc/tess4/NeuralNetsInTesseract4.00.html
[t-thread]: https://github.com/tesseract-ocr/tesseract/blob/5.5.3/include/tesseract/baseapi.h
[t-confidence]: https://github.com/tesseract-ocr/tesseract/blob/5.5.3/src/ccmain/ltrresultiterator.cpp
[t-opencl]: https://github.com/tesseract-ocr/tesseract/pull/4220
[t-data]: https://tesseract-ocr.github.io/tessdoc/Data-Files.html
[t-benchmark]: https://tesseract-ocr.github.io/tessdoc/Benchmarks.html
[t-ubuntu]: https://packages.ubuntu.com/noble/tesseract-ocr
[t-ubuntu-lib]: https://packages.ubuntu.com/noble/libtesseract5
[t-ubuntu-eng]: https://packages.ubuntu.com/noble/tesseract-ocr-eng
[t-ubuntu-osd]: https://packages.ubuntu.com/noble/tesseract-ocr-osd
[t-license]: https://github.com/tesseract-ocr/tesseract/blob/main/LICENSE
[tessdata-license]: https://github.com/tesseract-ocr/tessdata_fast/blob/main/LICENSE
[lept-license]: https://github.com/DanBloomberg/leptonica/blob/master/leptonica-license.txt

[p-release]: https://github.com/PaddlePaddle/PaddleOCR/releases/tag/v3.7.0
[p-output]: https://www.paddleocr.ai/v3.7.0/en/version3.x/pipeline_usage/OCR.html
[p-v6]: https://www.paddleocr.ai/v3.7.0/en/version3.x/algorithm/PP-OCRv6/PP-OCRv6.html
[p-sort]: https://github.com/PaddlePaddle/PaddleOCR/blob/v3.7.0/tools/infer/predict_system.py
[p-word]: https://raw.githubusercontent.com/PaddlePaddle/PaddleX/release/3.7/paddlex/inference/pipelines/ocr/pipeline.py
[p-det-score]: https://github.com/PaddlePaddle/PaddleOCR/blob/v3.7.0/ppocr/postprocess/db_postprocess.py
[p-rec-score]: https://github.com/PaddlePaddle/PaddleOCR/blob/v3.7.0/ppocr/postprocess/rec_postprocess.py
[p-layout]: https://www.paddleocr.ai/latest/en/version3.x/module_usage/layout_analysis.html
[p-doc-orient]: https://www.paddleocr.ai/latest/en/version3.x/pipeline_usage/doc_preprocessor.html
[p-line-orient]: https://www.paddleocr.ai/latest/en/version3.x/module_usage/textline_orientation_classification.html
[p-engines]: https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/local_inference/inference_engine.html
[p-hpi]: https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/local_inference/high_performance_inference.html
[p-cpp]: https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/local_inference/cpp/OCR.html
[p-cpp-issue]: https://github.com/PaddlePaddle/PaddleOCR/issues/18213
[p-thread]: https://www.paddlepaddle.org.cn/inference/guides/performance_tuning/multi_thread.html
[p-footprint]: https://www.paddleocr.ai/latest/en/version3.x/paddleocr_and_paddlex.html
[p-license]: https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE
[paddle-license]: https://github.com/PaddlePaddle/Paddle/blob/develop/LICENSE
[p-det-card]: https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx
[p-rec-card]: https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx

[r-release]: https://github.com/RapidAI/RapidOCR/releases/tag/v3.10.0
[r-39]: https://rapidai.github.io/RapidOCRDocs/main/changelog/v3.9.0/
[r-output]: https://rapidai.github.io/RapidOCRDocs/main/quickstart/
[r-main]: https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/main.py
[r-models]: https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/default_models.yaml
[r-word]: https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/cal_rec_boxes/main.py
[r-sort]: https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/ch_ppocr_det/main.py
[r-word-score]: https://github.com/RapidAI/RapidOCR/pull/750
[r-word-rotation]: https://github.com/RapidAI/RapidOCR/pull/747
[r-v6-cls]: https://github.com/RapidAI/RapidOCR/commit/9fe06b676cf691c948d5bba5084c2e7abe862c33
[r-lock]: https://github.com/RapidAI/RapidOCR/commit/486ec538d3c5196ff95864f501bc56916dcf4ba5
[r-trt]: https://rapidai.github.io/RapidOCRDocs/main/blog/2026/07/05/support-pp-ocrv6-tensorrt-engine/
[r-pypi]: https://pypi.org/pypi/rapidocr/3.10.0/json
[r-license]: https://github.com/RapidAI/RapidOCR/blob/main/LICENSE
[r-model-license]: https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/MODEL_LICENSES.md
[ro-release]: https://github.com/RapidAI/RapidOcrOnnx/releases
[ro-maint]: https://github.com/RapidAI/RapidOcrOnnx/issues/33
[ro-v5]: https://github.com/RapidAI/RapidOcrOnnx/issues/38

[ort-releases]: https://github.com/microsoft/onnxruntime/releases/tag/v1.31.0
[ort-api]: https://onnxruntime.ai/docs/api/
[ort-c]: https://onnxruntime.ai/docs/get-started/with-c.html
[ort-thread]: https://onnxruntime.ai/docs/api/c/struct_ort_ep.html
[ort-license]: https://github.com/microsoft/onnxruntime/blob/main/LICENSE
[ort-notices]: https://github.com/microsoft/onnxruntime/blob/main/ThirdPartyNotices.txt

[opencv-license]: https://github.com/opencv/opencv-python/blob/master/README.md
[shapely-license]: https://github.com/shapely/shapely/blob/main/README.rst
[icdar]: http://rrc.cvc.uab.es/?ch=4&com=tasks
