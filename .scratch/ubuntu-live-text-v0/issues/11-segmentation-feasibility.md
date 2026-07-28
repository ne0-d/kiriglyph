# 11: Select a local interactive segmentation adapter

**What to build:** Maintainers can choose a V0 model that turns a point or
drawn-region prompt into a useful subject mask locally on Ubuntu CPU, with
measured quality, latency, size, licensing, and runtime constraints.

**Blocked by:** 10: Publish the Text milestone acceptance evidence.

**Status:** blocked

- [ ] A bounded candidate set includes maintained interactive segmentation
  models with point or box prompting and a viable local Python or ONNX path.
- [ ] The benchmark separates one-time model load, per-image embedding, first
  mask, and subsequent prompt latency.
- [ ] A pinned, non-sensitive fixture corpus covers people, animals, products,
  overlapping subjects, holes, fine boundaries, low contrast, and
  no-clear-subject cases.
- [ ] Mask quality, stability across nearby prompts, CPU memory, model size,
  licence, model-asset distribution, and offline behavior are recorded.
- [ ] The adapter contract remains model-neutral and returns image dimensions,
  mask encoding, bounds, confidence or stability metadata, and timings.
- [ ] Cancellation, timeout, malformed output, process death, and model-load
  failure are recoverable and do not retain embeddings after the session.
- [ ] The decision selects one V0 adapter or blocks subject lifting with a
  precise technical reason; it does not declare the production winner.
