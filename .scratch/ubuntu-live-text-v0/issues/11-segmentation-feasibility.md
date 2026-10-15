# 11: Select a local interactive segmentation adapter

**What to build:** Maintainers can choose a V0 model that turns a point or
drawn-region prompt into a useful subject mask locally on Ubuntu CPU, with
measured quality, latency, size, licensing, and runtime constraints.

**Blocked by:** none (the overlay, 18, is resolved); can run in parallel with 09 and 21

**Status:** resolved

- [x] A bounded candidate set includes maintained interactive segmentation
  models with point or box prompting and a viable local Python or ONNX path.
- [x] The benchmark separates one-time model load, per-image embedding, first
  mask, and subsequent prompt latency.
- [x] A pinned, non-sensitive fixture corpus covers people, animals, products,
  overlapping subjects, holes, fine boundaries, low contrast, and
  no-clear-subject cases.
- [x] Mask quality, stability across nearby prompts, CPU memory, model size,
  licence, model-asset distribution, and offline behavior are recorded.
- [x] The adapter contract remains model-neutral and returns image dimensions,
  mask encoding, bounds, confidence or stability metadata, and timings.
- [x] Cancellation, timeout, malformed output, process death, and model-load
  failure are recoverable and do not retain embeddings after the session.
- [x] The decision selects one V0 adapter or blocks subject lifting with a
  precise technical reason; it does not declare the production winner.

Decision: use EfficientSAM-Ti as the V0 issue-12 adapter candidate. Evidence is
in [the benchmark report](../research/11-segmentation-benchmark.md). Remaining
unproven work is deliberately scoped to issue 12: real screenshot quality,
transparent PNG edge polish, in-worker cancellation, and UI responsiveness while
encoding.
