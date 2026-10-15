# Development Workflow Playbook

This project uses **fit-for-purpose compute**: select the model that best matches the task's reasoning needs. Quality comes first; cost and latency break ties between models that can perform the work equally well.

## Default operating mode

- The main chat runs on **Claude Sonnet 5.5 High** as a fixed orchestrator.
  It talks with the user, keeps specs and issues current, reviews sub-agent
  output, verifies results, diagnoses integration bugs, and makes small edits.
  Cursor Auto is not used for the main chat: it does not know this policy and
  can switch to a weaker model mid-way through a cross-layer debugging session.
- The main chat delegates substantial implementation to a sub-agent on the
  best-fit model below rather than writing it itself, and escalates by
  spawning a stronger sub-agent rather than asking the user to switch models.
- Agent mode is normal for implementation with explicit scope and verification.
- Plan mode is required for unresolved architecture, broad requirements, or hard-to-reverse choices.
- The user controls the parent-chat model. Project rules guide delegation but cannot enforce Cursor's model picker or billing.

### Main chat does directly

- Questions, explanations, issue and spec edits, and reviews of sub-agent diffs.
- Edits of roughly one file or under about 50 lines, and runtime diagnosis
  that needs back-and-forth with the user's desktop.
- Running verification (tests, analyzer, builds) before reporting completion.

### Main chat delegates

- Any ticket implementation spanning several files or a new subsystem.
- Independent work that can run in parallel with disjoint file ownership.
- Bounded research questions.

## Model routing

The mappings below are starting points, not hard assignments. Escalate or switch models whenever actual output quality shows a mismatch. No model must fail a fixed number of times before escalation.

### Composer 2.5 Fast

Use for repository exploration, straightforward Flutter or GTK UI, DTOs, serializers, mocks, fixture loaders, routine tests, documentation, CI configuration, and mechanical fixes while it remains accurate and complete.

### Cursor Grok 4.6 High Fast

Use for one bounded documentation question or primary-source lookup. Limit research to the sources necessary to answer that question; do not create broad landscape reports unless the ticket explicitly requires one.

### GPT-5.5 Medium

Use for cross-file features, D-Bus contracts after architecture is agreed, OCR adapters, process supervision, packaging, integration tests, benchmark harnesses, and non-trivial debugging with runtime evidence. It is also the immediate fallback when a fast coding model starts producing integration mistakes.

GPT-5.6 Terra Medium is a peer option for these tasks and should be selected whenever its reasoning profile better fits the work.

### Claude Opus 5.5 Medium

Use for component boundaries, Wayland and portal lifecycles, concurrency protocols, privacy and security analysis, accessibility architecture, ADRs, and decisions where rework would be expensive.

Claude Sonnet 5.5 High is suitable for difficult implementation, accessibility work, and independent review. Claude Opus 5.5 Medium is preferred when system-level reasoning or hard-to-reverse decisions dominate.

### GPT-5.6 Sol

Use for exceptionally difficult multi-system implementation, security-sensitive native failures, final architecture arbitration, or any task where maximum depth is proportionate to the risk. State the reason before invoking it; a failed lower-tier attempt is not required.

Other available models may be used when their demonstrated strengths fit a bounded task. The table is guidance, not an allowlist.

Prefer the newest generation in each family. Older generations (for example
Claude Opus 4.x or GPT-5.4) are not used when a newer peer is available.

### Cost discipline

- Choose the lowest tier that is expected to get the task right the first
  time; a failed cheap attempt plus a redo costs more than the right tier.
- Do not use Opus or Sol for UI layout, theming, tests, docs, or mechanical
  edits.
- Do not run two agents on the same question unless a comparison is the point.
- Reuse a finished sub-agent with `resume` for follow-up fixes on its own
  work instead of briefing a new one.

## Project task mapping

| Task | Default model |
| --- | --- |
| Search, inventory, simple UI, boilerplate, routine tests | Composer 2.5 Fast initially; escalate on quality mismatch |
| Narrow external API or package research | Cursor Grok 4.6 High Fast |
| Cross-file implementation, D-Bus, adapters, packaging | GPT-5.5 Medium or GPT-5.6 Terra Medium |
| Difficult implementation or independent review | Claude Sonnet 5.5 High |
| Architecture, concurrency, Wayland, privacy, accessibility | Claude Opus 5.5 Medium |
| Maximum-depth, high-risk engineering | GPT-5.6 Sol |
| Main chat orchestration, review, small fixes | Claude Sonnet 5.5 High |

Current tickets:

| Ticket | Model |
| --- | --- |
| 09 Overlay keyboard and screen reader | Claude Sonnet 5.5 High |
| 21 Remove manual image workflow (deletions, test rewrites) | Composer 2.5 Fast, escalate to GPT-5.5 Medium on mistakes |
| 10 Text acceptance (measurement harness, privacy tests) | GPT-5.5 Medium |
| 11 Segmentation feasibility | Cursor Grok 4.6 High Fast for sources, GPT-5.5 Medium for the benchmark |
| 12 Subject mode in the overlay | GPT-5.5 Medium, Claude Opus 5.5 Medium for the worker/embedding lifecycle if it grows |
| 13 Transparent PNG export, clipboard and save from the overlay | GPT-5.5 Medium |
| 14 Combined acceptance | GPT-5.5 Medium |

Finished: 15 (GPT-5.5 Medium), 16 and 17 and 18 (Claude Opus 5.5 Medium), 19
(GPT-5.5 Medium), 20 (GPT-5.5 Medium).

## Sub-agent policy

Sub-agents are encouraged when independent work can proceed concurrently or a specialist context improves quality.

Every invocation must:

1. Set the model explicitly; never use `inherit`.
2. Define one concrete deliverable.
3. Name allowed files or state that the task is read-only.
4. Bound sources and output size for research.
5. Define acceptance evidence and a stop condition.

Choose concurrency from the number of genuinely independent tasks and the cost of integrating their results. Keep each task bounded, avoid duplicate work unless comparison is intentional, and reserve parallel maximum-depth agents for cases where their independent conclusions justify the coordination cost.

Use direct search and file tools instead of a sub-agent for narrow lookups.

## Prompt contract

Substantial implementation prompts should define:

```text
Model tier:
Goal:
In scope:
Out of scope:
Done when:
Verification:
Stop conditions:
```

Delegation is chosen during execution when it adds specialization or safe parallelism. Do not precommit to avoiding sub-agents merely to reduce compute.

Change strategy or escalate instead of looping when:

- evidence shows the selected model or approach is producing repeated mistakes;
- scope unexpectedly crosses more than five files or introduces a subsystem;
- an unresolved product or architecture decision blocks correct implementation;
- verification cannot be made deterministic; or
- permissions, authentication, or missing environment capabilities block progress.

## Verification budget

Verification proves the work; it is not a ritual. Delegated prompts must carry
these limits:

- While working, run only the tests for the code being changed.
- Run the analyzer, formatter, and the full suite once at the end. Do not run
  the full suite several times in a row unless a flaky test is the subject of
  the task.
- Render visual evidence only when geometry or painting changed, and look at it
  once. Do not regenerate it after unrelated edits.
- Do not add evidence tables, ablations, or measurements the ticket did not ask
  for. Report numbers the decision needs.
- Time-box debugging: after two failed attempts on one hypothesis, change
  approach or report. Do not retry the same command.
- The reviewer (main chat) verifies the result once; agents do not duplicate
  that review.

## Quality controls

- Research should prefer current primary sources and distinguish facts, inference, and unresolved prototype questions.
- Architecture decisions require evidence from research or prototypes.
- Features and bug fixes use red-green-refactor where practical.
- Completion claims require fresh verification output.
- Existing research is extended, not repeated.
