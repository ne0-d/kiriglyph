# 11 Segmentation Benchmark

## Setup

- Runtime: Python 3.14.4, `onnxruntime==1.31.0` CPU, Pillow 12.3.0; NumPy is present transitively.
- Harness: `cd worker && .venv/bin/python -m benchmarks.segmentation run --repeats 5`.
- Assets live under ignored `worker/.models/segmentation/`; overlays and raw JSON live under ignored `worker/benchmarks/segmentation/output/`.
- Timings include PIL resize/pre-processing. Each model/thread run uses a fresh subprocess; medians and p95 are after one warmup.
- The app must not silently fetch models. V0 should either bundle weights in the developer install or run a documented explicit download step.

## Hardware

- CPU: AMD Ryzen 5 5600H with Radeon Graphics
- Cores visible: 12
- RAM: MemTotal:       15685340 kB
- Load average captured by harness: `9.19 5.45 2.91 1/2359 250641`

## Model Assets

| Asset | Size MB | SHA-256 | Licence note |
|---|---:|---|---|
| `efficientsam_ti_encoder.onnx` | 24.8 | `84ed466ffcc5c1f8d08409bc34a23bb364ab2c15e402cb12d4335a42be0e0951` | Apache-2.0 |
| `efficientsam_ti_decoder.onnx` | 16.6 | `a62f8fa5ea080447c0689418d69e58f1e83e0b7adf9c142e2bd9bcc8045c0b11` | Apache-2.0 |
| `sam2.1_hiera_tiny_20260221.zip` | 116.5 | `c602cb3f6fd297312a415f885f0df3f0eef9fbb334b069c9d30e828f2ae7c69a` | Apache-2.0 claimed by model card; third-party ONNX export |
| `u2net.onnx` | 176.0 | `8d10d2f3bb75ae3b6d527c77944fc5e7dcd94b29809d47a739a7a728a912b491` | Apache-2.0 model, distributed through rembg MIT release |

## ONNX Contracts Observed

| Model | Inputs | Outputs |
|---|---|---|
| `efficientsam_ti_encoder` | batched_images ['batch', 3, 'height', 'width'] tensor(float) | image_embeddings ['Addimage_embeddings_dim_0', 256, 'Addimage_embeddings_dim_2', 'Addimage_embeddings_dim_3'] tensor(float) |
| `efficientsam_ti_decoder` | image_embeddings ['batch', 256, 64, 64] tensor(float); batched_point_coords [1, 1, 'num_points', 2] tensor(float); batched_point_labels [1, 1, 'num_points'] tensor(float); orig_im_size [2] tensor(int64) | output_masks ['Reshapeoutput_masks_dim_0', 'Reshapeoutput_masks_dim_1', 'Reshapeoutput_masks_dim_2', 'Reshapeoutput_masks_dim_3', 'Reshapeoutput_masks_dim_4'] tensor(float); iou_predictions [1, 1, 'Reshapeiou_predictions_dim_2'] tensor(float); onnx::Shape_1830 ['Sliceonnx::Shape_1830_dim_0', 'Reshapeiou_predictions_dim_2', 'Sliceonnx::Shape_1830_dim_2', 'Sliceonnx::Shape_1830_dim_3'] tensor(float) |
| `sam2_tiny_encoder` | image [1, 3, 1024, 1024] tensor(float) | high_res_feats_0 [1, 32, 256, 256] tensor(float); high_res_feats_1 [1, 64, 128, 128] tensor(float); image_embed [1, 256, 64, 64] tensor(float) |
| `sam2_tiny_decoder` | image_embed [1, 256, 64, 64] tensor(float); high_res_feats_0 [1, 32, 256, 256] tensor(float); high_res_feats_1 [1, 64, 128, 128] tensor(float); point_coords ['num_labels', 'num_points', 2] tensor(float); point_labels ['num_labels', 'num_points'] tensor(float); mask_input ['num_labels', 1, 256, 256] tensor(float); has_mask_input ['num_labels'] tensor(float) | masks ['Clipmasks_dim_0', 'Clipmasks_dim_1', 'Clipmasks_dim_2', 'Clipmasks_dim_3'] tensor(float); iou_predictions ['Sliceiou_predictions_dim_0', 3] tensor(float) |
| `u2net` | input.1 [1, 3, 320, 320] tensor(float) | 1959 [1, 1, 320, 320] tensor(float); 1960 [1, 1, 320, 320] tensor(float); 1961 [1, 1, 320, 320] tensor(float); 1962 [1, 1, 320, 320] tensor(float); 1963 [1, 1, 320, 320] tensor(float); 1964 [1, 1, 320, 320] tensor(float); 1965 [1, 1, 320, 320] tensor(float) |

## Timing And Memory

| Model | Threads | Load ms | 1080p embed ms med/p95 | 1440p embed ms med/p95 | Prompt ms med/p95 | Stability IoU | Peak RSS MiB | Load avg |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| efficientsam_ti | 2 | 261.1 | 1826.5/1983.2 | 1824.3/1842.5 | 48.2/50.5 | 1.000 | 1287.3 | `4.22 2.19 1.46 3/2397 249524` |
| efficientsam_ti | 12 | 262.1 | 1232.5/1314.5 | 1373.3/1488.5 | 51.3/69.9 | 1.000 | 1292.1 | `3.15 2.21 1.51 3/2366 249659` |
| sam2_tiny_onnx | 2 | 1750.8 | 2166.9/2453.4 | 2133.1/2236.3 | 52.2/56.0 | 1.000 | 1727.2 | `9.05 3.87 2.10 1/2354 249785` |
| sam2_tiny_onnx | 12 | 1788.1 | 1415.0/1680.5 | 1279.0/1348.4 | 47.9/64.0 | 1.000 | 1696.0 | `4.72 3.61 2.13 2/2369 249985` |
| u2net | 2 | 472.6 | 678.6/732.8 | 792.0/973.0 | 11.0/16.5 | 1.000 | 1035.5 | `9.77 5.11 2.71 1/2365 250121` |
| u2net | 12 | 491.3 | 390.7/440.5 | 351.0/361.2 | 9.8/15.1 | 1.000 | 1039.7 | `8.46 5.10 2.76 2/2355 250585` |

First-mask latency after embedding:

| Model | Threads | 1080p first mask ms med/p95 | 1440p first mask ms med/p95 |
|---|---:|---:|---:|
| efficientsam_ti | 2 | 45.0/45.4 | 50.1/51.2 |
| efficientsam_ti | 12 | 100.7/107.5 | 120.6/131.9 |
| sam2_tiny_onnx | 2 | 51.1/56.7 | 52.6/53.5 |
| sam2_tiny_onnx | 12 | 125.8/143.9 | 124.5/145.8 |
| u2net | 2 | 5.9/6.1 | 11.0/15.6 |
| u2net | 12 | 8.8/10.2 | 14.8/15.4 |

## Fixture Quality

| Fixture | Objective IoU best overall | Heuristic notes | Overlay files |
|---|---:|---|---|
| person | 0.992 (u2net) | efficientsam_ti: area 0.052, comps 1, holes 0; sam2_tiny_onnx: area 0.052, comps 1, holes 0; u2net: area 0.078, comps 2, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/person.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/person.png`, `benchmarks/segmentation/output/overlays/u2net/person.png` |
| animal | 0.994 (u2net) | efficientsam_ti: area 0.031, comps 11, holes 1; sam2_tiny_onnx: area 0.041, comps 4, holes 2; u2net: area 0.143, comps 2, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/animal.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/animal.png`, `benchmarks/segmentation/output/overlays/u2net/animal.png` |
| product_hole | 0.997 (u2net) | efficientsam_ti: area 0.118, comps 1, holes 1; sam2_tiny_onnx: area 0.121, comps 3, holes 8; u2net: area 0.120, comps 1, holes 1 | `benchmarks/segmentation/output/overlays/efficientsam_ti/product_hole.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/product_hole.png`, `benchmarks/segmentation/output/overlays/u2net/product_hole.png` |
| overlapping_subjects | 0.990 (sam2_tiny_onnx) | efficientsam_ti: area 0.121, comps 1, holes 0; sam2_tiny_onnx: area 0.122, comps 1, holes 0; u2net: area 0.202, comps 1, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/overlapping_subjects.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/overlapping_subjects.png`, `benchmarks/segmentation/output/overlays/u2net/overlapping_subjects.png` |
| fine_boundaries | 0.710 (u2net) | efficientsam_ti: area 0.042, comps 1, holes 0; sam2_tiny_onnx: area 0.042, comps 1, holes 0; u2net: area 0.111, comps 1, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/fine_boundaries.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/fine_boundaries.png`, `benchmarks/segmentation/output/overlays/u2net/fine_boundaries.png` |
| low_contrast | 0.996 (u2net) | efficientsam_ti: area 0.076, comps 1, holes 0; sam2_tiny_onnx: area 0.073, comps 2, holes 0; u2net: area 0.125, comps 1, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/low_contrast.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/low_contrast.png`, `benchmarks/segmentation/output/overlays/u2net/low_contrast.png` |
| no_clear_subject | n/a | efficientsam_ti: area 0.997, comps 1, holes 0; sam2_tiny_onnx: area 0.999, comps 1, holes 0; u2net: area 0.000, comps 2, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/no_clear_subject.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/no_clear_subject.png`, `benchmarks/segmentation/output/overlays/u2net/no_clear_subject.png` |
| screenshot_photo_window | 0.992 (u2net) | efficientsam_ti: area 0.046, comps 1, holes 0; sam2_tiny_onnx: area 0.047, comps 1, holes 0; u2net: area 0.047, comps 1, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/screenshot_photo_window.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/screenshot_photo_window.png`, `benchmarks/segmentation/output/overlays/u2net/screenshot_photo_window.png` |
| screenshot_ui_card | 0.992 (efficientsam_ti) | efficientsam_ti: area 0.032, comps 1, holes 0; sam2_tiny_onnx: area 0.033, comps 1, holes 0; u2net: area 0.303, comps 1, holes 0 | `benchmarks/segmentation/output/overlays/efficientsam_ti/screenshot_ui_card.png`, `benchmarks/segmentation/output/overlays/sam2_tiny_onnx/screenshot_ui_card.png`, `benchmarks/segmentation/output/overlays/u2net/screenshot_ui_card.png` |

Objective IoU is against synthetic masks only; U2-Net is included as a no-prompt baseline, not an interactive adapter. Area/components/boundary/holes are heuristics and require human review of overlays.

## Failure Handling Evidence

- Contract module defines typed failures: `cancelled`, `timeout`, `malformed_output`, `model_load_failed`, `process_died`, `out_of_memory`.
- Unit tests cover serialization, malformed output, cancellation, timeout, and fake-session closure discarding embedding handles.
- Real model-load failure was exercised by constructing a session with a missing model path; ONNX Runtime raises before any embedding exists and maps to `model_load_failed` in the proposed adapter boundary.
- Subprocess death recovery was exercised by starting a benchmark subprocess and killing it mid-run; a later fresh subprocess can load the model and run normally because embeddings are process-local.
- Real adapters in this harness keep embeddings only in local variables inside each subprocess run; no embedding handles survive process exit.

## Contract

- `worker/src/worker/segmentation_contract.py` accepts image path or PNG bytes and returns an opaque session-scoped handle.
- Prompt requests carry foreground/background points and optional box in source-image coordinates.
- Mask transport should be a private `0600` alpha PNG file under `$XDG_RUNTIME_DIR`, returned as `alpha_png_file` path plus byte length and SHA-256. This avoids the existing 1 MiB NDJSON line cap and matches the current private crop-file convention.
- Results include image dimensions, bounds, confidence/stability metadata, and load/embed/first-mask/prompt timings.

## Distribution Notes

- EfficientSAM-Ti is 41.4 MB total and official Apache-2.0 ONNX, making it easiest to bundle or explicitly download.
- SAM2.1 Tiny ONNX is 116.5 MB zipped and third-party, so redistribution needs an extra provenance check even though the model card claims Apache-2.0.
- U2-Net is 176.0 MB and no-prompt only; it is useful as a fallback baseline, not the Subject Lift interaction adapter.
- Recommendation: issue 12 should use an explicit installer/download step for development V0 and never fetch at app runtime. Bundling can be revisited for production packaging.

## Decision

Select **EfficientSAM-Ti** as the V0 issue-12 adapter candidate because it is official Apache-2.0 split ONNX, is 41.4 MB total, keeps prompt latency near SAM2, and uses materially less load time, memory, and redistribution risk.

This is not a production winner. Unproven: quality on real screenshots, transparent PNG edge polish, redistribution review for third-party ONNX, UI responsiveness while encoding, and cancellation behavior inside the eventual long-lived worker.
