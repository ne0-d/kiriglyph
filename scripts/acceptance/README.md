# Kiriglyph Acceptance Kit

These scripts are safe by default: they do not launch the GUI, capture the
screen, or show GNOME portal dialogs unless a documented user-run option says
so.

## Offline checks the agent can run

```bash
worker/.venv/bin/python scripts/acceptance/ocr-corpus-eval.py
worker/.venv/bin/python scripts/acceptance/segmentation-corpus-eval.py
python3 scripts/acceptance/privacy_check.py --self-test
bash scripts/acceptance/measure-resources.sh --self-test
```

OCR corpus output goes to
`.scratch/ubuntu-live-text-v0/evidence/ocr-corpus-results.md`. The Python step
writes `scripts/acceptance/output/ocr-corpus/ocr-results.json`, then runs:

```bash
cd app
OCR_CORPUS_RESULTS=../scripts/acceptance/output/ocr-corpus/ocr-results.json ../.tools/flutter/bin/flutter test test/tool/paragraph_corpus_eval_test.dart
```

Subject corpus output goes to
`.scratch/ubuntu-live-text-v0/evidence/subject-corpus-results.md`. It uses the
real `worker.segmentation_worker` protocol and expects EfficientSAM-Ti model
files under `KIRIGLYPH_MODELS_DIR` or `worker/.models`.

## User-run desktop checks

Resource measurement without automatic launches:

```bash
bash scripts/acceptance/measure-resources.sh --activations 50
```

The script prompts you to press the shortcut. To auto-run the installed
launcher instead:

```bash
bash scripts/acceptance/measure-resources.sh --auto 50
```

`--auto` runs `~/.local/bin/kiriglyph --select` repeatedly. This flashes the
screen every time and needs the one-time GNOME screenshot grant to already be
accepted.

Privacy check after a session:

```bash
python3 scripts/acceptance/privacy_check.py --canary 'YOUR-CANARY-TEXT'
```

The privacy check scans Kiriglyph config/data/state/cache locations, recent
tagged journal logs, `$XDG_RUNTIME_DIR`, `~/Pictures`, crash dump locations, and
Kiriglyph process sockets. It never prints file contents.
