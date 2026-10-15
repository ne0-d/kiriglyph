# Interactive segmentation candidates for Subject Lift

Question: which point- or box-prompted models have a viable fully-local
CPU path on the Kiriglyph worker (Python 3.14, `onnxruntime==1.31.0` CPU
in `worker/.venv`), and which no-prompt salient-object ONNX is a fallback
when the user supplies no click? Ticket
[11](../issues/11-segmentation-feasibility.md); Subject stories 15–17 in
[spec](../spec.md). One embedding per capture, cheap later prompts.

Worker already has a cp314 ORT wheel:
`onnxruntime-1.31.0-cp314-cp314-manylinux_2_28_x86_64.whl`
([PyPI 1.31.0](https://pypi.org/project/onnxruntime/1.31.0/)).
Do not add PyTorch. Do not `pip install rembg` (README requires
`python >=3.11, <3.14`; PyPI `rembg==2.0.85` metadata is `>=3.11,<4.0`).

Sizes below are HTTP `Content-Length` of the named file (not downloaded).

## Comparison

| Model | Prompts | Code / weights | Ckpt | Official split ONNX | Enc vs prompt | Input | Published speed |
|---|---|---|---|---|---|---|---|
| SAM 2.1 Tiny / Small | Point, box, mask refine | Apache-2.0 both | 156.0 / 184.4 MB `.pt` | None from Meta | `set_image` then `predict` | 1024 | **GPU:** 91.2 / 84.8 FPS on A100 |
| MobileSAM | Point, box | Apache-2.0 both | 40.7 MB `mobile_sam.pt` | Decoder-only export | Tiny-ViT embed, SAM decoder | 1024 | **GPU:** 8+4=12 ms. **CPU:** ~3 s Mac i5 |
| EdgeSAM-3x | Point, box | **NTU S-Lab 1.0 NC** | 38.8 MB `.pth` | Yes, HF Space | Official enc+dec ONNX | 1024 | **GPU:** 164.3 FPS 2080 Ti. **Device:** 38.7 FPS iPhone 14 |
| EfficientSAM-Ti / S | Point, box | Apache-2.0 both | Ti `.pt` 41.0 MB | Yes, HF `yunyangx` | Official enc+dec ONNX | 1024 | **GPU:** ~20× vs SAM on A100 (S); no CPU figure |
| SAM ViT-B | Point, box, mask | Apache-2.0 both | 375.0 MB `.pth` | Official **decoder only** | Heavy ViT-B embed | 1024 | **GPU:** 452+4=456 ms (MobileSAM table) |
| rembg U²-Net / IS-Net / BiRefNet-lite | None (salient / whole FG) | rembg MIT; U²-Net Apache-2.0; IS-Net Apache-2.0 per rembg; BiRefNet MIT. **Skip `bria-rmbg` (paid commercial)** | 176.0 / 178.6 / 224.0 MB ONNX | Single-shot ONNX | No prompt decoder | U²-Net 320; others unresolved | No official CPU ms |

Third-party ONNX (not Meta): `vietanhdev/segment-anything-2.1-onnx-models`
(`sam2.1_hiera_tiny_20260221.zip` 116.5 MB, Apache-2.0 claimed) and
`vietanhdev/segment-anything-onnx-models` (`mobile_sam_20230629.zip` 36.7 MB;
`sam_vit_b_01ec64.zip` 348.4 MB).

## Per-candidate notes

### SAM 2.1 Tiny / Small (Meta)

- Repo / card: https://github.com/facebookresearch/sam2
  https://huggingface.co/facebook/sam2.1-hiera-tiny (`license: apache-2.0`)
- Weights: https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_tiny.pt
  (`sam2.1_hiera_small.pt` sibling). Code+ckpts Apache-2.0.
- Official install wants `python>=3.10`, `torch>=2.5.1`; no official ONNX
  ([issue 508](https://github.com/facebookresearch/sam2/issues/508)).
- Image path: encode once (`SAM2ImagePredictor.set_image`), then point/box
  `predict`. Config `image_size: 1024`.
- FPS table is A100 + `torch 2.5.1, cuda 12.4`, not CPU.

### MobileSAM

- https://github.com/ChaoningZhang/MobileSAM Apache-2.0 LICENSE +
  `weights/mobile_sam.pt` (40.7 MB).
- Official `scripts/export_onnx_model.py` exports **prompt encoder + mask
  decoder only** (inputs include `image_embeddings`). Encoder ONNX is
  unofficial (HF zip above or self-export).
- Same SAM interfaces: point, box, `set_image` then `predict`.
- GPU 12 ms and Mac i5 ~3 s are from the official README.

### EdgeSAM — licence block for redistribution

- https://github.com/chongzhou96/EdgeSAM NTU S-Lab License 1.0:
  non-commercial only; commercial needs the authors.
- Official ONNX:
  https://huggingface.co/spaces/chongzhou/EdgeSAM/resolve/main/weights/edge_sam_3x_encoder.onnx
  (22.1 MB) and `edge_sam_3x_decoder.onnx` (15.9 MB). Tested ORT `1.16.3`.
- Encoder `1x3x1024x1024` → `1x256x64x64`; decoder takes points/boxes.
- 22.1 GFLOPs / 9.6 M params. Fastest published device path; **do not
  ship** without a licence change.

### EfficientSAM-Ti / S

- https://github.com/yformer/EfficientSAM Apache-2.0 LICENSE.
  HF card https://huggingface.co/yunyangx/EfficientSAM also `apache-2.0`.
- Official split ONNX (HF Space announcement in README):
  `efficientsam_ti_encoder.onnx` 24.8 MB,
  `efficientsam_ti_decoder.onnx` 16.6 MB,
  `efficientsam_s_encoder.onnx` 89.6 MB,
  `efficientsam_s_decoder.onnx` 16.6 MB.
- `.pt`: https://github.com/yformer/EfficientSAM/raw/main/weights/efficient_sam_vitt.pt
- Prompts: point and box. Paper throughput is NVIDIA A100, 1024², one box;
  EfficientSAM-S ~20× vs SAM. No CPU ms.

### SAM ViT-B (official ONNX decoder)

- https://github.com/facebookresearch/segment-anything Apache-2.0.
  https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth
  (375.0 MB).
- Official export is decoder-only; encoder stays PyTorch unless using the
  348.4 MB third-party zip or rembg
  `vit_b-encoder-quant.onnx` (99.8 MB) + `vit_b-decoder-quant.onnx` (8.7 MB).
- Too large for the V0 CPU overlay; quality reference only.

### No-prompt fallback (rembg assets, not the rembg package)

- rembg MIT: https://github.com/danielgatis/rembg
  Models: https://github.com/danielgatis/rembg/releases/tag/v0.0.0
- **U²-Net** Apache-2.0 (https://github.com/xuebinqin/U-2-Net):
  `u2net.onnx` 176.0 MB; keep pretrained input **320×320**.
  Light: `u2netp.onnx` 4.6 MB.
- **IS-Net** `isnet-general-use.onnx` 178.6 MB; rembg maintainer says
  Apache-2.0 via https://github.com/xuebinqin/DIS (raw LICENSE 404 here).
- **BiRefNet-lite** MIT (https://github.com/ZhengPeng7/BiRefNet):
  `BiRefNet-general-bb_swin_v1_tiny-epoch_232.onnx` 224.0 MB.
- **Do not use** default `bria-rmbg-2.0.onnx` (~1 GB, paid commercial).
- Whole-image salient FG only: no click/box, no reusable embedding.

## FACTS / INFERENCE / UNRESOLVED

**FACTS (cited above).** ORT 1.31.0 publishes cp314 manylinux wheels and
is already imported in `worker/.venv` (Python 3.14.4). Meta SAM / SAM2
and EfficientSAM / MobileSAM are Apache-2.0. EdgeSAM is non-commercial.
Meta ships no SAM2 ONNX. EfficientSAM and EdgeSAM ship split encoder /
decoder ONNX. Official SAM/MobileSAM ONNX is decoder-only. U²-Net
pretrained SOD expects 320². rembg README excludes Python 3.14 even
though PyPI `requires_python` is looser. All listed GPU/device times are
**not** Ubuntu CPU.

**INFERENCE.** A V0 adapter should run ONNX on the pinned ORT, encode
once after capture, and reuse the embedding for click/box refine. SAM2
Tiny is the quality bet; EfficientSAM-Ti is the size/setup bet. rembg
ONNX is only the no-prompt path. EdgeSAM would likely win latency if the
licence were acceptable.

**UNRESOLVED (benchmark only).** Ubuntu CPU encode-ms and prompt-ms on
1920×1080 / 2560×1440 crops; peak RSS; mask quality on people / products
/ holes / low contrast; SAM2 third-party ONNX numerical match; IS-Net /
BiRefNet input size and CPU time; whether 320² U²-Net is usable on a
screenshot; whether nearby clicks are stable.

## Shortlist to benchmark (3)

Keep `onnxruntime==1.31.0` and `pillow==12.3.0`. No new pip packages.

1. **EfficientSAM-Ti** — only prompted candidate with official Apache-2.0
   split ONNX small enough for a warm resident worker.
   - https://huggingface.co/yunyangx/EfficientSAM/resolve/main/efficientsam_ti_encoder.onnx
   - https://huggingface.co/yunyangx/EfficientSAM/resolve/main/efficientsam_ti_decoder.onnx
2. **SAM 2.1 Tiny (third-party ONNX)** — current Meta image model,
   Apache-2.0 weights; unofficial export, so treat as a quality spike.
   - https://huggingface.co/vietanhdev/segment-anything-2.1-onnx-models/resolve/main/sam2.1_hiera_tiny_20260221.zip
     (unzip to `encoder.onnx` + `decoder.onnx`)
   - Official `.pt` (do not run unless adding torch):
     https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_tiny.pt
3. **U²-Net ONNX** — no-prompt fallback; Apache-2.0; single ORT session.
   - https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx
   Optional quality twin:
   https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx

Measure separately: model load, per-image encode, first mask, later
prompt. Do not pick a production winner from this note.
