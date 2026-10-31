# Contributing to Kiriglyph

Bug reports and ideas are welcome as GitHub issues. This page covers sending code. How to build and run the app is in the [README](README.md#install-from-source), and how it works is in [How it works](README.md#how-it-works).

## Before you open a pull request

1. Set up the project: `./scripts/bootstrap.sh`, then `./scripts/run-dev.sh` to run it from source.
2. Make your change. Add or update tests with it; behaviour that touches the UI or the GNOME desktop needs a test with a fake, not the real thing.
3. Run the full check and make sure it prints `CHECK PASSED`:

   ```bash
   ./scripts/check.sh full --build
   ```

   While you work, `./scripts/check.sh quick <test files>` runs format, analyze, and just the tests you list. Tool paths and gotchas (the repository path may contain spaces) are in [docs/agents/dev-commands.md](docs/agents/dev-commands.md).
4. If you changed packaging, build the package (`./scripts/build-deb.sh`) and try it on a clean Ubuntu with [`scripts/acceptance/deb-clean-room/run.sh`](scripts/acceptance/README.md#package-clean-room-check); it needs no root or VM.
5. Describe what changed and why. If the change was hard to reverse or took a real decision, add a record to [`docs/adr/`](docs/adr/).

## Tests never touch your real settings

The app reads and writes your config folder and your GNOME keyboard shortcuts. So `app/test/flutter_test_config.dart` installs an in-memory settings store and a fake shortcut service before every test file. A test that needs different behaviour overrides the provider itself. Never run the real `gsettings` from a test; to try it by hand, use a throwaway store: `GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME=$(mktemp -d) gsettings ...`.

## Issues, specifications, and decisions

Issues and specifications are plain Markdown under `.scratch/` ([how it works](docs/agents/issue-tracker.md)): one file per issue, with acceptance boxes you tick as evidence arrives. Words with a specific meaning in this project are in [`GLOSSARY.md`](GLOSSARY.md).

Acceptance checks that flash the real screen, such as the black-frame check on a real desktop, are run by hand: [`scripts/acceptance/`](scripts/acceptance/README.md).

## Licence

Kiriglyph is under the [Apache License 2.0](LICENSE). By sending a contribution you agree that it is licensed the same way, as section 5 of the licence provides. There is no separate agreement to sign. A new dependency needs a licence compatible with that; check it before you add it, and mention it in the pull request.
