# Dev commands

Read this before running anything in the repo. It holds the gotchas no config file states.

## Gotchas

- The repo path contains spaces. Quote it everywhere. zsh does not split unquoted variables.
- Flutter is the repo-local SDK: `.tools/flutter/bin/flutter`, run from `app/`.
- Python worker tooling: `worker/.venv/bin/python`, package manager `.tools/uv-bin/uv`.
- Worker tests need `KIRIGLYPH_MODELS_DIR=.models/segmentation` and `PYTHONPATH=src`, run from `worker/`.
- Only one agent at a time runs `flutter build`; others run tests.
- Tests that decode images or call `toImage` need `tester.runAsync`. Test fonts render as solid boxes.

## The check command

`scripts/check.sh` decides whether work is done.

| Command | Runs |
| --- | --- |
| `scripts/check.sh quick [test files]` | format, analyze, the listed app tests |
| `scripts/check.sh full` | format, analyze, full app tests, full worker tests |
| `scripts/check.sh full --build` | the above plus `flutter build linux --debug` |

Use `quick` with the test files for the code you are changing. Run `full` once at the end.
Delegated work is done when `scripts/check.sh full` prints `CHECK PASSED`.

## Fixtures

- Test images must be raw captures. Screenshots of Kiriglyph's own overlay contain painted dim and highlight pixels and are not valid segmentation sources.
- `scripts/capture-fixture.sh <name>` saves one raw capture to the git-ignored `worker/benchmarks/segmentation/fixtures/real/` directory.
- Fakes that stand in for the worker mirror the real worker's replies, including error codes (for example a recognize request on an image without text answers with the error `no_text`, not an empty result).
