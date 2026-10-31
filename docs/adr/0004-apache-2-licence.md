# 0004: Kiriglyph is licensed under Apache-2.0

**Status:** accepted. Applies from the first public release, 0.1.0.

## Context

The repository had no licence file, the README said none had been chosen, and
the package marked the application's licence as `UNVERIFIED`. Without a licence
nobody may legally use, copy or change the code, so the project could not be
opened up. Once people have a release under a licence they keep those rights
for that release, so the choice is hard to take back.

Everything Kiriglyph bundles is permissive: the Flutter engine and framework
(BSD-3-Clause), the Python wheels (MIT, BSD, Apache-2.0, MPL-2.0 for two small
ones), the Dart packages (MIT, BSD, Apache-2.0, and MPL-2.0 for the Canonical
`dbus`, `gtk` and `yaru` families), and the OCR and segmentation models
(Apache-2.0). Nothing forces a copyleft licence.

## Decision

License Kiriglyph under the **Apache License 2.0** (`Apache-2.0`).

- The `LICENSE` file holds the unmodified text, and `NOTICE` carries the
  copyright line (`Copyright 2026 Kiriglyph contributors`).
- The package copyright file is in the Debian machine-readable format and
  points at `/usr/share/common-licenses/Apache-2.0`. AppStream says
  `Apache-2.0`.
- Contributions are accepted under the same licence, as section 5 of the
  licence already provides. There is no contributor agreement.
- Third-party components keep their own licences. `packaging/generate_notice.py`
  inventories them in the `.deb`.

## Alternatives considered

- **MIT.** The shortest text, and just as permissive. It says nothing about
  patents, which matters in text recognition and image segmentation.
- **GPL-3.0.** The norm for GNOME applications. It would force anyone who ships
  a modified version, including a company repackaging it as a closed product, to
  publish their source. It would also make it harder to relicense contributors'
  code later, and it is no better matched to the models and libraries bundled
  here, which are all permissive.
- **No licence.** Not open source, and nobody could safely use the code.

## Consequences

- Anyone may use, modify, redistribute and sell Kiriglyph, including in closed
  products, as long as they keep the licence and notices. The project does not
  stop that.
- The copyright holder can still relicense their own code for future versions.
- The MPL-2.0 Dart and Python packages are used unmodified, so their file-level
  copyleft does not reach Kiriglyph's own files. If one is ever patched, the
  patched files must stay under MPL-2.0 and be published.
- The notice generator must keep reporting every bundled component, and a new
  dependency with a copyleft licence needs a new record before it is added.
