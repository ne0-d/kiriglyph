# Linux OCR UX landscape

**Ticket:** 05 — Linux OCR UX landscape  
**Scope:** maintained and historically relevant Linux screenshot/document OCR applications; GNOME HIG, GTK accessibility/input documentation, Libadwaita appearance guidance, and XDG desktop portal contracts.

## Method and evidence standard

This report uses primary, first-party sources only: project documentation and source code, project release/commit records, KDE and GNOME project pages, GNOME/GTK/Libadwaita documentation, and XDG Desktop Portal documentation. Source-code observations are pinned to immutable revisions wherever possible. Maintenance is reported as dated repository and release evidence, not as a popularity or quality claim.

The survey covers the four named products—NormCap, TextSnatcher, Frog, and gImageReader—and five current alternatives that materially broaden the landscape: dpScreenOCR, OCRmyPDF, ApexShot, KDE Spectacle, and Native Screenshot UI OCR Extended for GNOME Shell. OCRmyPDF represents the maintained document/batch pipeline; Spectacle and the GNOME extension represent desktop-integrated OCR; dpScreenOCR represents a current hotkey-first X11 design; and ApexShot represents a current cross-desktop beta.

No live installation, compositor matrix, keyboard-only walkthrough, or assistive-technology test was performed. “No evidence found” means the inspected first-party documentation and pinned source do not establish the property; it does **not** prove that the property is absent at runtime. Source-head behavior can also be newer than the most recent packaged release.

## Executive findings

1. **Wayland capture is no longer one mechanism.** NormCap mixes a non-interactive Screenshot portal grab with a custom frozen-screen overlay and a `grim` path; TextSnatcher, Frog, and current gImageReader source use an interactive Screenshot portal; ApexShot chooses among KWin, wlroots, Screenshot portal, and ScreenCast/PipeWire paths; Spectacle is KWin-specific on Wayland; and the GNOME extension runs inside GNOME Shell through private screenshot UI internals. These are materially different portability and consent models, despite all being described as “Wayland support.” [NormCap portal source][normcap-portal] [TextSnatcher OCR/capture source][textsnatcher-tesseract] [Frog screenshot service][frog-screenshot] [gImageReader GTK capture source][gimagereader-gtk-capture] [ApexShot Wayland backend][apexshot-wayland] [Spectacle README][spectacle-readme] [GNOME extension capture source][gnome-ocr-processor]

2. **The dominant screenshot-OCR interaction is “select region → get plain text,” not spatial Live Text.** NormCap, TextSnatcher, Frog, dpScreenOCR, ApexShot, Spectacle, and the GNOME extension ultimately expose a text string through a clipboard, result view, history, or notification. gImageReader is the closest surveyed tool to spatial text interaction because its hOCR document workflow associates recognized items with image regions, but it is a document workbench rather than a transient desktop overlay. [NormCap README][normcap-readme] [TextSnatcher README][textsnatcher-readme] [Frog README][frog-readme] [dpScreenOCR manual][dpscreenocr-manual] [ApexShot README][apexshot-readme] [Spectacle OCR source][spectacle-ocr] [GNOME extension source][gnome-ocr-extension] [gImageReader README][gimagereader-readme]

3. **Keyboard and accessibility evidence is the main landscape gap.** Spectacle and ApexShot implement keyboard movement/resizing once a region exists, while Frog exposes ordinary GTK/Libadwaita controls and application shortcuts. None of the surveyed projects publishes an Orca, AT-SPI, high-contrast, display-off, or complete keyboard-only acceptance result at the inspected revisions. Portal use delegates the selector to the desktop but does not, by itself, prove that an application’s complete flow is accessible. [Spectacle selection editor][spectacle-selection] [ApexShot overlay events][apexshot-overlay-events] [Frog window source][frog-window] [GTK accessibility documentation][gtk-accessibility]

4. **Document OCR is a different product category.** gImageReader provides interactive import, scanning, layout definition, hOCR editing, spellcheck, and searchable-document output, while OCRmyPDF is a keyboard/script-driven conversion pipeline for searchable PDF/PDF-A with sidecars and explicit exit codes. Neither supplies a desktop selection overlay. [gImageReader README][gimagereader-readme] [OCRmyPDF introduction][ocrmypdf-intro] [OCRmyPDF API][ocrmypdf-api] [OCRmyPDF exit codes][ocrmypdf-exit-codes]

5. **Maintenance evidence is uneven.** Dated activity is current in 2026 for NormCap source, gImageReader source, dpScreenOCR, OCRmyPDF, ApexShot, Spectacle, and the surveyed GNOME extension. Frog’s last inspected commit and release are in 2025. TextSnatcher’s last inspected commit is 2024 and its latest release is from 2022, so current maintenance cannot be inferred from the available dates. [NormCap commit][normcap-commit] [gImageReader commit][gimagereader-commit] [dpScreenOCR commit][dpscreenocr-commit] [OCRmyPDF commit][ocrmypdf-commit] [ApexShot commit][apexshot-commit] [KDE Spectacle releases][spectacle-app-page] [GNOME extension commit][gnome-ocr-commit] [Frog commit][frog-commit] [TextSnatcher commit][textsnatcher-commit]

6. **There is no surveyed cross-desktop tool that simultaneously demonstrates portal-native GNOME Wayland capture, a complete keyboard-only region flow, explicit screen-reader semantics, spatial word-level interaction, and privacy-minimal defaults.** The individual pieces exist across projects—portal capture in Frog/gImageReader, keyboard geometry in Spectacle/ApexShot, hOCR structure in gImageReader, and temporary-file deletion in several tools—but not as one documented, tested workflow. [Frog screenshot service][frog-screenshot] [gImageReader GTK capture source][gimagereader-gtk-capture] [Spectacle selection editor][spectacle-selection] [ApexShot overlay events][apexshot-overlay-events] [gImageReader README][gimagereader-readme] [GNOME extension capture source][gnome-ocr-processor]

## Wayland support taxonomy

The labels below are analytical classifications used consistently in this report:

- **Portal-backed:** capture is requested through `org.freedesktop.portal.Screenshot` or ScreenCast and therefore depends on the installed desktop portal backend.
- **Native protocol:** the application talks directly to a Wayland protocol such as wlroots screencopy.
- **Compositor-specific:** the application depends on a compositor service or shell implementation such as KWin ScreenShot2 or GNOME Shell private screenshot internals.
- **Mixed:** the application chooses among more than one of the above.
- **Unsupported:** the project explicitly excludes Wayland.
- **Not applicable:** there is no screen-capture feature.
- **Unclear:** first-party evidence is insufficient to classify the behavior.

The Screenshot portal’s current version 3 advertises screen, user-selected window, user-selected area, and active-window targets; `interactive` is only a hint, and the result is a screenshot URI. Applications must inspect the runtime interface version and `AvailableTargets` instead of assuming version 3 is deployed. [Screenshot portal contract][portal-screenshot]

## Comparison matrix

| Tool | Product/stack and OCR engine | Wayland classification | Main interaction and packaging | Maintenance evidence and license | Accessibility evidence and principal gaps |
|---|---|---|---|---|---|
| **NormCap** | Python 3.10+, PySide6/Qt; Tesseract plus ZXing QR detection. [Project metadata][normcap-pyproject] | **Mixed:** non-interactive Screenshot portal full-desktop capture followed by a custom Qt overlay; optional wlroots `grim`; other handlers exist for desktop-specific/X11 cases. [Capture selection][normcap-screenshot-main] [Portal handler][normcap-portal] [grim handler][normcap-grim] | Pointer-drag frozen-screen selection, OCR to clipboard, parse/raw modes; Flathub, AUR, PyPI, and a deprecated AppImage path are documented. [README][normcap-readme] | Source commit 2026-07-10; v0.6.0 released 2025-08-31; GPL-3.0-or-later. [Commit][normcap-commit] [Release][normcap-release] [License][normcap-license] | `Escape` cancellation is evidenced, but region creation is mouse-event driven and no keyboard geometry or AT test is documented. Full-desktop capture precedes selection; the portal file is deleted on the successful read path. [GUI source tree][normcap-gui] [Portal handler][normcap-portal] |
| **TextSnatcher** | Vala/C, GTK 3, Granite, libhandy, libportal; Tesseract command line. [Build source][textsnatcher-meson] [OCR source][textsnatcher-tesseract] | **Portal-backed** on Wayland with interactive selection; X11 uses `scrot -s`. [OCR/capture source][textsnatcher-tesseract] | “Snatch” opens screenshot, file, or clipboard-image choices; recognized text is copied automatically and status replaces the title. Project documentation covers elementary/Ubuntu-oriented packages and Flatpak build material. [Selection screen][textsnatcher-select] [OCR source][textsnatcher-tesseract] [README][textsnatcher-readme] | Last inspected commit 2024-03-20; v2.0.0 released 2022-03-15. **License metadata is inconsistent:** the root license is GPLv3, while source headers say GPL-2.0-or-later. These dates do not demonstrate current maintenance in 2026. [Commit][textsnatcher-commit] [Release][textsnatcher-releases] [License][textsnatcher-license] [Source header][textsnatcher-app] | Standard GTK controls provide a baseline, but no app shortcuts or AT tests are documented. UI strings are hardcoded; OCR uses a single command-line string parsed by GLib and writes `~/.textsnatcher.txt`; screenshot/output cleanup is not consistently established. [Home screen][textsnatcher-home] [OCR source][textsnatcher-tesseract] |
| **Frog** | Python/PyGObject, GTK 4, Libadwaita, Blueprint; pytesseract/Pillow and pyzbar. [README][frog-readme] [Build source][frog-meson] | **Portal-backed:** libportal interactive Screenshot request; returned screenshot is removed after processing. [Screenshot service][frog-screenshot] | In-window extract/import, result editing/copying, QR handling, text-to-speech/share actions and shortcut window; distributed through Flathub and Snap. [README][frog-readme] [Window source][frog-window] | Last inspected commit 2025-05-15; v1.6.0 released 2025-04-24; MIT. The dates show a maintained 2025 release line but not 2026 activity. [Commit][frog-commit] [Release][frog-release] [License][frog-license] | Strongest GNOME-application baseline in the screenshot group: standard GTK/Adwaita controls, gettext catalog, shortcuts, and toasts. No published Orca/high-contrast/keyboard-only capture test was found. Telemetry is active by default, creates an installation identity, and sends events to EU PostHog; screenshot pixels/text are not shown in the inspected telemetry call sites. Optional gTTS and share actions can disclose recognized text externally when invoked. [Telemetry service][frog-telemetry] [Settings schema][frog-settings-schema] [Screenshot service][frog-screenshot] [TTS service][frog-tts] [Share service][frog-share] |
| **gImageReader** | C++17; GTKmm 3 or Qt 5/6 front ends; Tesseract library. [README][gimagereader-readme] [Build source][gimagereader-cmake] | **Portal-backed in pinned source:** both GTK and Qt source use interactive Screenshot portal capture on Wayland and remove the returned image; non-Wayland paths capture screens directly. [GTK source][gimagereader-gtk-capture] [Qt source][gimagereader-qt-capture] | Document/image/scanner/clipboard/screenshot import; manual or automatic regions; plain text and hOCR editing; searchable PDF and other exports. Source releases, Fedora/Debian repositories, Ubuntu PPA, OBS, and Arch GTK/Qt packages are documented. [README][gimagereader-readme] | Source commit 2026-09-29; v3.4.3 released 2025-08-04; GPL-3.0-or-later. Portal behavior is evidenced at source head and may postdate v3.4.3 packages. [Commit][gimagereader-commit] [Release][gimagereader-release] [License][gimagereader-license] | Standard toolkit widgets, menu actions, and automatic whole-page/layout recognition create keyboard alternatives for some tasks. Precise manual region creation remains pointer-oriented, and no app-level AT acceptance evidence was found. [GTK displayer source][gimagereader-gtk-displayer] [Qt displayer source][gimagereader-qt-displayer] |
| **dpScreenOCR** | C++17, Qt 5/6, Tesseract. [Build source][dpscreenocr-cmake] | **Unsupported:** the manual explicitly states that GNU/Linux screen capture currently works only on X11, not Wayland. [Manual][dpscreenocr-manual] | Global hotkey enters rectangle selection; pointer positions/resizes; hotkey completes and `Escape` cancels; output can go to clipboard, history, or configured actions. Debian/Ubuntu and other distro packages plus a self-contained GNU/Linux archive are documented. [Manual][dpscreenocr-manual] | Source commit 2026-10-04; v1.5.1 released 2026-05-24; zlib-style license. [Commit][dpscreenocr-commit] [Release][dpscreenocr-release] [License][dpscreenocr-license] | Global keyboard start/finish is good, but region geometry is pointer-dependent and no AT evidence was found. Recognition history is persisted in the user configuration area unless disabled/cleared, which is a privacy-sensitive default for captured text. [Manual][dpscreenocr-manual] |
| **OCRmyPDF** | Python 3.11+ CLI/library; Tesseract with pikepdf, pypdfium2/Ghostscript and related PDF tooling. [Installation docs][ocrmypdf-install] [Architecture docs][ocrmypdf-architecture] | **Not applicable:** it processes files and streams; it does not capture the desktop. [Introduction][ocrmypdf-intro] | Batch/script/API conversion to searchable PDF/PDF-A, optional text sidecar and preprocessing. Debian/Ubuntu/Fedora, PyPI/uv, Homebrew, Snap, and x86_64/arm64 containers are documented. [Installation docs][ocrmypdf-install] [Docker docs][ocrmypdf-docker] | Source commit 2026-10-12; v17.13.0 released 2026-09-28; MPL-2.0. [Commit][ocrmypdf-commit] [Release][ocrmypdf-release] [License][ocrmypdf-license] | Excellent keyboard/scriptability and a typed exit-code/error contract, but no GUI, overlay, focus, or screen-reader widget semantics. Official security guidance says PDFs should be treated as potentially malicious and untrusted processing should be isolated. [Exit codes][ocrmypdf-exit-codes] [Errors][ocrmypdf-errors] [Security docs][ocrmypdf-security] |
| **ApexShot** | Rust/GTK 4/layer-shell application plus C++17/Qt overlay; Tesseract primary OCR and `ocrs`/RTen fallback. [Cargo metadata][apexshot-cargo] [OCR fallback][apexshot-ocrs] | **Mixed:** KWin ScreenShot2, direct wlroots screencopy, Screenshot portal, then ScreenCast/PipeWire fallback; optional GNOME Shell integration adds compositor-specific behavior. [Wayland backend][apexshot-wayland] [README][apexshot-readme] | Screenshot/annotation/recording suite with OCR-to-clipboard. Release assets include `.deb`, Arch and Fedora packages; Nix/source instructions are documented. [README][apexshot-readme] [Release][apexshot-release] | Source commit 2026-10-12; v0.2.35 released 2026-09-06; GPL-3.0-or-later; README explicitly labels the product public beta. [Commit][apexshot-commit] [Release][apexshot-release] [Cargo metadata][apexshot-cargo] | Once a region exists, arrows move it, Shift+arrows resize it, Enter/Space accepts and `Escape` cancels. The overlay is extensively custom drawn; initial keyboard-only region creation, focus order, accessible names/roles, and AT tests are not established. The fallback neural OCR engine downloads and caches models on first use, so every OCR configuration is not strictly offline from first launch. [Overlay events][apexshot-overlay-events] [OCR fallback][apexshot-ocrs] |
| **KDE Spectacle 6.6+** | C++20, Qt 6/QML, KDE Frameworks; Tesseract is linked by the current build. [Root build source][spectacle-root-cmake] [Application build source][spectacle-cmake] | **Compositor-specific on Wayland:** designed for KDE/KWin; the project states that use on non-KDE desktops is an X11 case. [README][spectacle-readme] | “Extract Text” operates on a capture/viewer image, copies recognized text, supports OCR language choice and reports outcomes; Spectacle is delivered through KDE’s release service and distro packaging. [Plasma 6.6 announcement][spectacle-plasma-66] [OCR source][spectacle-ocr] [KDE app page][spectacle-app-page] | Source commit 2026-10-12; v6.7.5 released 2026-09-08; AppStream declares GPL-2.0-or-later (`GPL-2.0+`), with file-level SPDX licenses. [Commit][spectacle-commit] [KDE app page][spectacle-app-page] [AppStream metadata][spectacle-appdata] [License inventory][spectacle-licenses] | Best documented region keyboard mechanics in the survey: arrows move, Alt+arrows resize, Shift gives a fine step, and Enter accepts. No first-party screen-reader/AT acceptance evidence was found for the custom capture overlay or OCR result flow. [Selection editor][spectacle-selection] |
| **Native Screenshot UI OCR Extended** | GJS/JavaScript GNOME Shell extension; Tesseract subprocess. [Metadata][gnome-ocr-metadata] [Processor][gnome-ocr-processor] | **Compositor-specific:** drives GNOME Shell’s native screenshot UI in process and patches private UI/save methods; it is not a portal client. [Extension source][gnome-ocr-extension] [Processor][gnome-ocr-processor] | Panel icon, rebindable global shortcut, or toggle injected into `PrtSc`; area selection, local OCR, clipboard, optional result notification. Packaged on extensions.gnome.org and as release ZIPs; supports Shell 45–50. [README][gnome-ocr-readme] [GNOME Extensions listing][gnome-ocr-ego] | Commit and v0.1.2 release both dated 2026-07-09; GPL-2.0-or-later. [Commit][gnome-ocr-commit] [Release][gnome-ocr-release] [README][gnome-ocr-readme] | Native selector reuse and a global shortcut are useful, and cancellation/no-text/missing-engine/failure states are distinguished. The default icon-only injected button has no explicit accessible label in source, user-facing strings are not gettext-marked, private Shell internals are brittle, and success notifications include up to 100 characters of recognized text. [Extension source][gnome-ocr-extension] |

## Detailed tool observations

### 1. NormCap

- **Stack, engine, and license.** The project metadata requires Python 3.10 and PySide6, declares Tesseract/PyTesseract-related OCR dependencies and ZXing support, and identifies GPL-3.0-or-later licensing. [Project metadata][normcap-pyproject] [License][normcap-license]
- **Wayland path.** The selection logic chooses among handlers by environment. Its portal handler requests a screenshot with `interactive=false`, reads the returned full screenshot URI, and tries to delete that file after loading it. A separate `grim` handler is available for wlroots environments. The application then presents its own transparent/full-screen Qt windows over the frozen image, so this is **portal-backed capture plus a custom overlay**, not a portal-provided area selector. [Capture selection][normcap-screenshot-main] [Portal handler][normcap-portal] [grim handler][normcap-grim]
- **Interaction.** The documented flow is launch, drag a rectangle, release, and receive text on the clipboard; “parse” mode tries to normalize text, while raw mode preserves detected layout more closely. Desktop-wide invocation is delegated to an operating-system shortcut rather than an application-managed global shortcut. [README][normcap-readme]
- **Packaging.** The project directs Linux users primarily to Flathub, also lists AUR/PyPI, and marks the AppImage route deprecated. [README][normcap-readme]
- **Maintenance.** The inspected revision was committed on 2026-07-10, while the latest release is v0.6.0 from 2025-08-31. Those dates show that the release line lags behind the inspected source activity. [Commit][normcap-commit] [Release][normcap-release]
- **Accessibility and UX evidence.** Selection-window source is centered on pointer press/move/release, with `Escape` as the clear keyboard affordance. No source-level keyboard region geometry, tab sequence, accessible role/name setup, or published AT test was found in the inspected GUI tree. Notifications provide success/error feedback, but a clipboard-only output still needs a nonvisual confirmation channel. [GUI source tree][normcap-gui] [Notification source tree][normcap-notifications]
- **Privacy and gaps.** OCR is local and the portal file is deleted after a successful load, but a non-interactive full-desktop image is acquired before the user narrows the region. That creates a larger in-process sensitive-data surface than a version-3 portal request whose target is `Area`. The comparison is an architectural inference; the portal contract itself does not prohibit full-screen capture. [Portal handler][normcap-portal] [Screenshot portal contract][portal-screenshot]

### 2. TextSnatcher

- **Stack, engine, and license.** TextSnatcher is written in Vala against GTK 3, Granite/libhandy and libportal. OCR is invoked through the Tesseract command line. Upstream licensing is internally inconsistent: the root `LICENSE` contains GPLv3, while `src/Application.vala` says “version 2 … or (at your option) any later version.” Consumers should not silently collapse those statements into one SPDX expression; upstream clarification is needed. [Build source][textsnatcher-meson] [OCR source][textsnatcher-tesseract] [License][textsnatcher-license] [Source header][textsnatcher-app]
- **Wayland path.** Under Wayland, the OCR/capture service constructs an interactive libportal screenshot request; the X11 path calls `scrot -s`. This is a **portal-backed** Wayland design, with the desktop providing area selection. [OCR/capture source][textsnatcher-tesseract]
- **Interaction and packaging.** “Snatch Now” leads to screenshot, file, or clipboard-image choices. Recognition runs asynchronously, writes a text result, copies nonempty output to the clipboard automatically, and replaces the title with status text; there is no result editor in the inspected source. First-party documentation covers elementary OS/Ubuntu-oriented installation and Flatpak build/install steps. [Home screen][textsnatcher-home] [Selection screen][textsnatcher-select] [Main screen][textsnatcher-main-screen] [OCR source][textsnatcher-tesseract] [README][textsnatcher-readme]
- **Maintenance.** The latest inspected commit is dated 2024-03-20 and the latest project release is v2.0.0 from 2022-03-15. This is insufficient evidence to call the project currently maintained. [Commit][textsnatcher-commit] [Releases][textsnatcher-releases]
- **Accessibility and localization.** Standard GTK buttons and text controls carry toolkit semantics, but the inspected app sources do not establish accelerators, a shortcut window, explicit accessible names beyond visible labels, or AT testing. User-facing strings are directly embedded rather than consistently marked for gettext, so localization evidence is weak. [Home screen][textsnatcher-home] [Main screen][textsnatcher-main-screen]
- **Privacy, robustness, and errors.** OCR source assembles a single command-line string for parsing by GLib and writes OCR output to `~/.textsnatcher.txt`; returned screenshot paths and generated output are not covered by a clear always-delete lifecycle. This is both a path-handling robustness gap and a privacy-retention gap. The UI has error text, but no documented error taxonomy separates cancellation, portal denial, no text, missing language data, Tesseract failure, and clipboard failure. [OCR source][textsnatcher-tesseract]

### 3. Frog

- **Stack, engine, and license.** Frog is a Python/PyGObject application using GTK 4 and Libadwaita; screenshot processing uses Pillow, pytesseract and pyzbar. The project is MIT-licensed. [README][frog-readme] [Screenshot service][frog-screenshot] [License][frog-license]
- **Wayland path.** `Xdp.Portal.take_screenshot()` is called with the interactive flag. The returned URI is decoded, OCR/QR processing runs locally, and the screenshot is removed in a `finally` block when the service owns the source. This is a clean **portal-backed** capture lifecycle. [Screenshot service][frog-screenshot]
- **Interaction and packaging.** Users can capture or import, inspect/edit the result, copy, share, or read it aloud. The application defines in-window shortcuts and supports an extract-on-launch command that can be bound externally. First-party documentation points to Flathub and Snap. [README][frog-readme] [Window source][frog-window] [Main source][frog-main]
- **Maintenance.** The last inspected commit is a translation update dated 2025-05-15, and v1.6.0 was released on 2025-04-24. This is positive 2025 maintenance evidence, but there is no inspected 2026 source or release activity. [Commit][frog-commit] [Release][frog-release]
- **Accessibility and localization.** Standard GTK/Adwaita controls inherit GTK’s accessibility baseline; Frog also has a shortcut presentation and gettext/Weblate translation infrastructure. Those are implementation advantages, not proof of a complete accessible flow. No published keyboard-only portal-selector, Orca, high-contrast, large-text, or display-off result was found. [Window source][frog-window] [Translation tree][frog-translations] [GTK accessibility documentation][gtk-accessibility]
- **Feedback and errors.** Screenshot failure, cancellation, decode failure, and no-text conditions are emitted as errors and rendered in application UI/toasts. Cancellation is currently surfaced as an error string rather than treated as a neutral completion. [Screenshot service][frog-screenshot] [Window source][frog-window]
- **Privacy.** OCR itself stays local in the inspected screenshot service, and temporary screenshot deletion is explicit. Invoking text-to-speech passes recognized text to gTTS and saves the returned speech audio; share actions place recognized text in an external provider URI. These are explicit user actions, but they are separate disclosure paths that “local OCR” does not describe. Separately, telemetry defaults active, creates an installation identifier, and sends event names/properties to EU PostHog; the inspected screenshot events include action/language metadata, not captured pixels or recognized text. The default-on telemetry and Flatpak network permission should be disclosed prominently for a privacy-sensitive capture utility. [Screenshot service][frog-screenshot] [TTS service][frog-tts] [Share service][frog-share] [Telemetry service][frog-telemetry] [Settings schema][frog-settings-schema] [Flatpak manifest][frog-flatpak]

### 4. gImageReader

- **Stack, engine, and license.** gImageReader is a C++17 Tesseract front end with separately buildable GTKmm 3 and Qt 5/6 interfaces. Project source is GPL-3.0-or-later. [README][gimagereader-readme] [Build source][gimagereader-cmake] [License][gimagereader-license]
- **Wayland path.** At the pinned source revision, both GTK and Qt source managers call the Screenshot portal interactively when running on Wayland, load the returned URI, and remove the portal image. Non-Wayland paths use toolkit/root-window capture. This is **portal-backed** on Wayland at source head. [GTK capture source][gimagereader-gtk-capture] [Qt capture source][gimagereader-qt-capture]
- **Interaction.** The application is a document workbench: import from image/PDF/scanner/clipboard/screenshot, define recognition regions manually or automatically, recognize multiple pages, edit plain text or hOCR, spellcheck, and export searchable documents. hOCR’s region tree is the strongest spatial-text precedent in this survey, but it is post-capture document editing rather than direct interaction with words on the desktop. [README][gimagereader-readme]
- **Packaging.** The project documents source releases, Fedora and Debian repositories, an Ubuntu PPA, OpenSUSE Build Service, and separate Arch GTK/Qt packages. [README][gimagereader-readme]
- **Maintenance.** Source commit 046641b is dated 2026-09-29. Latest release v3.4.3 is dated 2025-08-04. The report therefore treats the portal implementation as current-source evidence; downstream v3.4.3 binaries must not be assumed to contain every inspected source-head change. [Commit][gimagereader-commit] [Release][gimagereader-release]
- **Accessibility and gaps.** The application uses standard widgets and exposes menu/toolbar actions, while whole-page and automatic layout recognition reduce the need for precise pointer input. Manual creation, movement and resizing of image regions is implemented primarily through pointer events; no complete keyboard-region or AT test result was found. The two front ends may also differ in platform accessibility behavior, so “gImageReader” should not be treated as one verified accessibility surface. [GTK displayer source][gimagereader-gtk-displayer] [Qt displayer source][gimagereader-qt-displayer]

### 5. dpScreenOCR

- **Stack, engine, and license.** dpScreenOCR is a C++17 Qt application using Tesseract, under a short permissive zlib-style license. [Build source][dpscreenocr-cmake] [License][dpscreenocr-license]
- **Wayland path.** The project manual is explicit: GNU/Linux capture currently supports X11 only and does not support Wayland. It is therefore **unsupported**, not “unclear” or portal-backed. [Manual][dpscreenocr-manual]
- **Interaction.** A global hotkey begins selection, the pointer positions/resizes the box, another hotkey invocation completes recognition, and `Escape` cancels. Results can be copied, retained in history, or sent to a configured executable. This is an efficient hotkey-first model but not a keyboard-only geometry model. [Manual][dpscreenocr-manual]
- **Packaging and maintenance.** The manual documents Debian/Ubuntu and other distro packages plus self-contained archives. The inspected commit is dated 2026-10-04 and v1.5.1 was released 2026-05-24. [Manual][dpscreenocr-manual] [Commit][dpscreenocr-commit] [Release][dpscreenocr-release]
- **Accessibility and privacy.** Qt widgets provide a baseline for the history/settings window, but the core rectangle requires pointer geometry and no AT test evidence was found. Text history is stored under the user configuration directory unless the user changes/clears it; for sensitive captures, persistence should be opt-in rather than assumed harmless. [Manual][dpscreenocr-manual]
- **Errors and network behavior.** The application documents language/update download behavior and action execution. These are useful capabilities, but they add distinct failure states—offline language data, failed update/download, and failed external action—that a new design should not collapse into generic “OCR failed.” [Manual][dpscreenocr-manual]

### 6. OCRmyPDF

- **Stack, engine, and license.** OCRmyPDF is a Python 3.11+ command-line application and library. It orchestrates Tesseract and PDF tooling including pikepdf, pypdfium2 and Ghostscript-related paths. It is MPL-2.0 licensed. [Installation docs][ocrmypdf-install] [Architecture docs][ocrmypdf-architecture] [License][ocrmypdf-license]
- **Wayland and interaction.** Screen capture is outside its scope. Its interaction model is file/stream input, command options or Python API, and file/stream output. It adds a searchable text layer, can emit PDF/A and a sidecar text file, and is designed for batch automation. [Introduction][ocrmypdf-intro] [API][ocrmypdf-api]
- **Packaging.** Official documentation covers Debian/Ubuntu/Fedora packages, PyPI/uv, Homebrew, Snap, and Docker images for x86_64 and arm64. [Installation docs][ocrmypdf-install] [Docker docs][ocrmypdf-docker]
- **Maintenance.** The pinned commit is dated 2026-10-12 and prepares 17.13.1; the latest published release at research time is v17.13.0 from 2026-09-28. The distinction prevents attributing unreleased source behavior to the latest package. [Commit][ocrmypdf-commit] [Release][ocrmypdf-release]
- **Accessibility and errors.** A CLI is intrinsically keyboard/script driven and composes with terminal accessibility, but it supplies no graphical focus or screen-capture semantics. Its explicit exit-code enumeration distinguishes bad arguments, invalid input, missing dependencies, invalid output, access errors, prior OCR, child-process errors, encryption, invalid configuration, PDF/A conversion failure, generic failure, and interruption. That is a strong error-contract precedent for a GUI even though the presentation layer differs. [Exit codes][ocrmypdf-exit-codes] [Errors][ocrmypdf-errors]
- **Security.** Official documentation warns that PDF processing invokes a complex stack and recommends processing only trusted PDFs or isolating untrusted jobs. A desktop OCR product that later adds PDF import should inherit this threat model rather than treating document OCR as equivalent to a small bitmap crop. [Security docs][ocrmypdf-security]

### 7. ApexShot

- **Stack, engine, and license.** ApexShot combines a Rust GTK 4/layer-shell application with a bundled C++17/Qt capture overlay. Tesseract is the default OCR feature; an `ocrs`/RTen neural fallback is also present. Cargo metadata declares GPL-3.0-or-later. [Cargo metadata][apexshot-cargo] [OCR fallback][apexshot-ocrs]
- **Wayland path.** The backend documents an ordered still-image strategy: KWin ScreenShot2, direct wlroots screencopy, Screenshot portal, then ScreenCast portal/PipeWire. Portal-only builds skip compositor-private paths. It is correctly classified **mixed**, not generically “native Wayland.” [Wayland backend][apexshot-wayland]
- **Interaction and packaging.** ApexShot is a broad screenshot, annotation and recording suite whose OCR action copies extracted text. Release artifacts include Debian, Arch and Fedora formats; source/Nix paths are also documented. The README labels the project public beta, which is relevant maturity evidence independent of its recent activity. [README][apexshot-readme] [Release][apexshot-release]
- **Maintenance.** The inspected commit is dated 2026-10-12 and v0.2.35 was released 2026-09-06. [Commit][apexshot-commit] [Release][apexshot-release]
- **Keyboard and accessibility.** The custom overlay handles `Escape`, Enter/Return/Space, arrows to move an existing region, and Shift+arrows to resize. That is substantive keyboard evidence. The same overlay is a large custom-drawn surface, and the inspected source does not establish a keyboard method to create the initial nonempty selection in every mode, a tab order through drawn toolbar items, accessible names/roles, or AT tests. [Overlay events][apexshot-overlay-events]
- **Privacy and network behavior.** Tesseract OCR is local. The fallback neural engine downloads two models from an S3 endpoint on first use and caches them, so “offline OCR” is only accurate after assets are present or when Tesseract is used. Cloud upload is an optional broader product feature and should be kept visibly separate from OCR/copy actions. [OCR fallback][apexshot-ocrs] [README][apexshot-readme]

### 8. KDE Spectacle 6.6+

- **Stack, engine, and license.** Current source is C++20/Qt 6/QML with KDE Frameworks. The build links Tesseract for OCR. AppStream declares GPL-2.0-or-later (`GPL-2.0+`), while individual source files carry their own compatible SPDX identifiers. [Root build source][spectacle-root-cmake] [Application build source][spectacle-cmake] [AppStream metadata][spectacle-appdata] [License inventory][spectacle-licenses]
- **Wayland path.** Spectacle is KDE’s screenshot utility and uses KWin integration on Wayland; its README only claims non-KDE use for X11 environments. This is **KWin/compositor-specific**, not a generic portal solution for GNOME. [README][spectacle-readme] [KWin platform source][spectacle-kwin]
- **Interaction.** Plasma 6.6 introduced text extraction. Current source exposes “Extract Text,” initializes Tesseract languages, runs recognition asynchronously, copies nonempty text, and emits status/result signals used by the UI. [Plasma 6.6 announcement][spectacle-plasma-66] [OCR action][spectacle-ocr-action] [OCR source][spectacle-ocr]
- **Packaging and maintenance.** KDE’s application page records v6.7.5 on 2026-09-08; source commit 5693aaf is dated 2026-10-12. The repository says Spectacle is delivered through KDE’s release service; distro packages are the normal Linux distribution path. [KDE app page][spectacle-app-page] [Commit][spectacle-commit] [README][spectacle-readme]
- **Keyboard and accessibility.** The selection editor directly implements arrows to move, Alt+arrows to resize, Shift for device-pixel stepping, and Enter to accept. This is the strongest keyboard region manipulation in the survey and a useful behavior precedent. It does not establish the accessible tree, focusability, or screen-reader behavior of all QML overlay controls, and no project AT acceptance evidence was found. [Selection editor][spectacle-selection]
- **Gaps for this ticket.** Spectacle proves that local OCR can fit naturally into a mature screenshot workflow and that region geometry can be keyboard operable. Its KWin dependency and KDE/QML interaction model prevent it from serving as the implementation base for a GNOME/GTK application. [README][spectacle-readme] [KWin platform source][spectacle-kwin]

### 9. Native Screenshot UI OCR Extended

- **Stack, engine, and license.** This is a GJS GNOME Shell extension. It invokes an external `tesseract` subprocess and is GPL-2.0-or-later. [Metadata][gnome-ocr-metadata] [Processor][gnome-ocr-processor] [README][gnome-ocr-readme]
- **Wayland path.** It calls `Main.screenshotUI` inside GNOME Shell, temporarily replaces the private `_saveScreenshot()` method, uses `Shell.Screenshot.composite_to_stream()`, and restores the method after capture. Source comments explain that the public D-Bus screenshot methods reject arbitrary extension senders. This is **GNOME Shell/compositor-specific** and depends on private implementation details, not XDG portal capture. [Processor][gnome-ocr-processor] [Extension source][gnome-ocr-extension]
- **Interaction and packaging.** Users can click a panel icon, invoke a rebindable global shortcut, or toggle an OCR control injected into the native `PrtSc` UI. The extension restricts capture to an area, runs OCR, copies text, and optionally posts a transient notification. It is published on extensions.gnome.org for Shell 45–50 and has release ZIPs. [README][gnome-ocr-readme] [GNOME Extensions listing][gnome-ocr-ego] [Release][gnome-ocr-release]
- **Maintenance.** The inspected commit and v0.1.2 release are both dated 2026-07-09, providing recent maintenance evidence. [Commit][gnome-ocr-commit] [Release][gnome-ocr-release]
- **Accessibility and localization.** Reusing the native screenshot UI and providing a global shortcut reduce app-specific interaction, and the panel button supplies a descriptive Shell label. However, the default injected overlay control is icon-only with no explicit accessible name in source. User-facing strings are hardcoded rather than gettext-marked. There is no first-party keyboard-only selector or screen-reader test result. [Extension source][gnome-ocr-extension]
- **Feedback, privacy, and gaps.** The processor writes a UUID-named temporary PNG and deletes it in `finally`; cancellation is silent, while no text, missing Tesseract and generic OCR failure are distinct. Success notifications include the first 100 characters of recognized text. That preview is a privacy-sensitive default because GNOME notifications can appear outside the capture context; the setting to disable notifications is helpful but does not replace a safer metadata-only default. The privacy judgment is an inference grounded in the documented implementation and GNOME notification behavior. [Processor][gnome-ocr-processor] [Extension source][gnome-ocr-extension] [GNOME notification guidance][hig-notifications]

## Direct GNOME/GTK/platform guidance

This section contains only **documented guidance or API contracts**. GNOME HIG statements use “should” language and are official design guidance, not runtime-enforced rules. GTK and portal statements describe platform behavior/capabilities. Product-specific conclusions appear separately in the next section.

### Shortcuts and keyboard-only operation — documented HIG guidance

- Every pointer action should also be possible from the keyboard, every part of the interface should be keyboard navigable, focus order should be logical, and the app should be tested using only a keyboard. Custom UI should implement the standard navigation keys: Tab/Shift+Tab, Return, Space, F10, Menu/Shift+F10, and `Escape` for transient containers. [GNOME keyboard HIG][hig-keyboard]
- Use standard GNOME shortcuts where the corresponding actions exist. For nonstandard application shortcuts, GNOME recommends mnemonic `Ctrl`+letter combinations, warns against `Alt` conflicts with access keys, reserves `Super` for system shortcuts, and advises against awkward reaches. Labelled controls should have access keys where practical. [GNOME keyboard HIG][hig-keyboard]
- The standard shortcut reference includes `Ctrl+W` close, `Ctrl+Q` quit, F1 help, F10 menu, `Ctrl+?` keyboard shortcuts, `Ctrl+,` preferences, and standard editing keys such as `Ctrl+C`. It also lists legacy system-reserved combinations that applications should avoid. [GNOME standard shortcuts][hig-standard-shortcuts]
- Pointer operations should be cancellable with `Escape`; hover should not be the only way to reveal essential controls or information; click targets should tolerate low precision; and difficult interactions such as double-clicking or button chording should be avoided. [GNOME pointer/touch HIG][hig-pointer]

### Focus and activation — documented GTK/HIG behavior

- Each GTK window has one keyboard focus location. Tab and Shift+Tab move focus, many containers support directional arrow navigation, and Enter/Space activate standard controls. GTK documents keyboard input as key events delivered to the focus widget, with key bindings translating combinations into widget actions. [GTK input handling][gtk-input]
- When a dialog opens, initial focus should go to the component expected to be used first. A cancel action should respond to `Escape`; Return should activate an affirmative action only when that action is not destructive or otherwise inconvenient. Dialogs should be parented/modal and should not appear unexpectedly. [GNOME dialog HIG][hig-dialogs]

### Screen-reader semantics — documented GTK/HIG requirements

- All interface elements should have short, descriptive accessible names. GNOME recommends testing high contrast, large text, keyboard-only operation, screen-reader use including with the display off, and the on-screen keyboard. [GNOME accessibility HIG][hig-accessibility]
- Standard GTK controls implement `GtkAccessible` by default. Custom widgets must provide correct roles, states, properties and relations; an assigned role is a promise to provide the expected keyboard behavior. Icon-only buttons should have explicit localized labels, and nonstandard keyboard behavior should have accessible help text. [GTK accessibility documentation][gtk-accessibility]
- GTK exposes `BUSY`, `INVALID`, `DISABLED`, `SELECTED` and related states, plus `ERROR_MESSAGE`, `LABELLED_BY`, `DESCRIBED_BY` and other relations. These are the documented mechanisms for exposing processing and validation state to assistive technology. [GTK accessibility documentation][gtk-accessibility]
- `gtk_accessible_announce()` is specifically intended for screen-reader announcements of messages that have only a visual representation or successful operations, without unnecessarily interrupting current screen-reader output. It is available from GTK 4.14. [GTK announcement API][gtk-announce]

### Feedback, notifications, progress, and errors — documented HIG guidance

- Toasts are transient, dismissible, in-application feedback for individual events. Persistent states belong in banners. Notifications are for information valuable while the application is not active; they should be limited, user-controllable, removed when stale, and never the only place the information is communicated. [GNOME toast HIG][hig-toasts] [GNOME banner HIG][hig-banners] [GNOME notification HIG][hig-notifications]
- Error dialogs should be avoided for simple noncritical errors; a toast is often less disruptive. Dialogs are appropriate when it is essential that the user see and respond. Required choices should keep the affirmative action insensitive until the input is valid. [GNOME dialog HIG][hig-dialogs]
- Destructive actions should provide either confirmation or undo, with undo generally preferred; if undo is impossible, a confirmation dialog should identify the risk and preserve a cancel path. Destructive button styling is a warning treatment, and a view should contain at most one suggested or destructive-styled button. [GNOME dialog HIG][hig-dialogs] [GNOME toast HIG][hig-toasts] [GNOME button HIG][hig-buttons]
- Progress should be indicated when an operation takes roughly three seconds or longer. Spinners suit shorter indeterminate work; a progress bar is generally more appropriate beyond roughly 30 seconds, and destructive or resource-intensive work should consider pause/cancel actions. [GNOME spinner HIG][hig-spinners] [GNOME progress-bar HIG][hig-progress]

### Dark and high-contrast themes — documented HIG/Libadwaita guidance

- Most applications should follow the system light/dark preference; an image-rich application may prefer dark, and an app-level chooser should normally offer light, dark, and follow-system options. High-contrast mode should be tested. Custom styling should be minimized and should not use color as the only information channel. [GNOME UI styling HIG][hig-styling]
- Standard GTK/Libadwaita widgets automatically support dark and high-contrast appearances. Custom drawing must support them explicitly, using CSS variables/style colors instead of hardcoded colors and consulting `AdwStyleManager` or media queries when needed. [Libadwaita appearance documentation][libadwaita-appearance]

### Localization and writing — documented GNOME guidance

- UI text should be short, clear, consistent, task-oriented, and translatable. Sentences should not be assembled from fragments across controls, and Latin abbreviations that are difficult to translate or read aloud should be avoided. [GNOME writing style][hig-writing]
- Localization guidance calls for clear/simple terminology, consistent typography, translator comments for ambiguous strings, valid UTF-8, and no hardcoded line wrapping. [GNOME localization practices][gnome-localization]

### Capture and global shortcuts — documented portal contracts

- Screenshot portal version 3 advertises supported target types. A request includes a parent window, defaults to modal, can set an `interactive` hint, can request exactly one advertised target, and asynchronously returns a screenshot URI. `Window` and `Area` are explicitly user-selected targets. [Screenshot portal contract][portal-screenshot]
- Portal requests use request objects because they commonly involve user interaction and dialogs that can stay open. The method call returns an object-path handle; the request remains exported for the interaction, and completion arrives through its `Response` signal. [Portal request lifecycle][portal-requests]
- The GlobalShortcuts portal creates app-bound shortcut sessions. Binding normally presents configuration UI, accepts a user-readable description and optional preferred trigger, and may return any subset—including an empty set. Version 2 also supports a configure-shortcuts UI. [GlobalShortcuts portal contract][portal-global-shortcuts]

### Privacy boundary in the direct documentation

The inspected GNOME HIG pages do **not** state a dedicated OCR/screenshot rule such as “never retain captures,” “OCR must be local,” or “never include recognized text in a notification.” The portal contract defines platform-mediated targets, user-selected area/window options, request lifecycle, and a returned URI; it does not define the application’s retention, telemetry, clipboard, notification-content, or OCR-provider policy. Those choices below are therefore explicitly **inferred product recommendations**, not quoted GNOME requirements. [Screenshot portal contract][portal-screenshot] [Portal request lifecycle][portal-requests]

## Inferred product design recommendations for ticket 05

Everything in this section is an **inference** from the documented platform guidance and the surveyed product evidence. It is not represented as a direct GNOME requirement.

### Invocation and shortcuts

1. **Recommendation (inferred):** expose “Capture Text” as an ordinary in-app action and request a configurable desktop-wide binding through the GlobalShortcuts portal when the runtime backend supports it. Handle an empty binding result and offer clear desktop-settings instructions as a fallback. Do not silently seize a hardcoded accelerator. This follows the portal’s user-facing bind/configure model and avoids copying the Shell-extension pattern into a regular application. [GlobalShortcuts portal contract][portal-global-shortcuts] [GNOME keyboard HIG][hig-keyboard]
2. **Recommendation (inferred):** keep application accelerators consistent with GNOME (`Ctrl+?`, `Ctrl+,`, `Ctrl+W`, `Ctrl+C`) and avoid assigning `Super` from the application itself. If a Shell integration is ever offered, treat it as a separate, explicitly installed component with its own conflict UI. [GNOME keyboard HIG][hig-keyboard] [GNOME standard shortcuts][hig-standard-shortcuts]

### Capture and overlay flow

1. **Recommendation (inferred):** prefer Screenshot portal v3 with `target=Area`, a real parent window, and modal behavior. Detect interface version and `AvailableTargets`; fall back to the version-2 interactive path only when area targeting is unavailable. This minimizes the pixels delivered to the app while preserving compatibility. [Screenshot portal contract][portal-screenshot]
2. **Recommendation (inferred):** avoid GNOME Shell private APIs and compositor-specific protocols in the main application. The surveyed GNOME extension demonstrates excellent integration but also demonstrates the maintenance cost of patching `_saveScreenshot()` and private containers. [GNOME extension source][gnome-ocr-extension] [GNOME extension processor][gnome-ocr-processor]
3. **Recommendation (inferred):** if a custom frozen-screen overlay is necessary, give it an opaque interaction model: an accessible instruction, a visible selection, explicit Cancel and Extract actions, and no essential hover-only toolbar. `Escape` cancels immediately and Return accepts only when a valid region exists. [GNOME keyboard HIG][hig-keyboard] [GNOME pointer/touch HIG][hig-pointer] [GNOME dialog HIG][hig-dialogs]
4. **Recommendation (inferred):** support keyboard geometry using the proven Spectacle/ApexShot pattern: arrows move; a documented modifier plus arrows resizes; a precision modifier provides one-device-pixel steps; Tab reaches visible controls; Enter extracts; `Escape` cancels. Also provide non-geometric alternatives such as whole active window and full screen where the portal advertises them. The exact modifier mapping is a product decision, not prescribed by GNOME. [Spectacle selection editor][spectacle-selection] [ApexShot overlay events][apexshot-overlay-events] [Screenshot portal contract][portal-screenshot]

### Focus and screen-reader model

1. **Recommendation (inferred):** use standard GTK 4/Libadwaita controls for the window, result list, buttons, menus and settings. Treat any image/selection canvas as a custom accessible widget with a role, descriptive label, state, help text and keyboard actions. [GTK accessibility documentation][gtk-accessibility]
2. **Recommendation (inferred):** on capture start, focus the selection surface or first actionable target and announce concise instructions. On cancel or completion, restore focus to the initiating “Capture Text” action or result view. GTK’s single-focus model and HIG initial-focus guidance make untracked focus loss a defect, even though this exact OCR sequence is not specified by GNOME. [GTK input handling][gtk-input] [GNOME dialog HIG][hig-dialogs]
3. **Recommendation (inferred):** do not expose only a screenshot image or painted word boxes to assistive technology. Present recognized content in reading order as selectable text, with each block/line associated with its visual bounds and with keyboard actions for select, copy and activate. Use a standard text/list representation as the primary accessible surface; visual bounding boxes are a synchronized secondary view. This combines gImageReader’s hOCR precedent with GTK’s custom-widget requirements. [gImageReader README][gimagereader-readme] [GTK accessibility documentation][gtk-accessibility]
4. **Recommendation (inferred):** announce “Text copied,” “No text found,” and actionable failures with `gtk_accessible_announce()` in addition to visual feedback. Avoid reading the recognized payload aloud automatically, because it may be sensitive and lengthy. [GTK announcement API][gtk-announce]

### Feedback and error states

1. **Recommendation (inferred):** treat user cancellation as a normal outcome, not an error. Distinguish at least: portal unavailable, user/portal denial, capture failure, no recognizable text, missing OCR engine/language, OCR timeout/failure, clipboard failure, and unsafe/unsupported document input. The surveyed extension and OCRmyPDF provide useful precedents for explicit categories. [GNOME extension source][gnome-ocr-extension] [OCRmyPDF exit codes][ocrmypdf-exit-codes]
2. **Recommendation (inferred):** use an in-app toast plus accessible announcement for quick success (“Text copied”) while the window is active; use a persistent banner for missing engine/language setup; reserve a system notification for completion that remains valuable while the app is inactive. Never make a notification the only feedback channel. [GNOME toast HIG][hig-toasts] [GNOME banner HIG][hig-banners] [GNOME notification HIG][hig-notifications]
3. **Recommendation (inferred):** do not put recognized text in notification bodies by default. A metadata-only message such as “Text copied” avoids lock-screen or shoulder-surfing disclosure; an opt-in preview can be offered with a clear warning. This is a privacy recommendation, not a direct HIG rule. [GNOME notification HIG][hig-notifications] [GNOME extension source][gnome-ocr-extension]
4. **Recommendation (inferred):** show a delayed spinner if OCR exceeds about three seconds and expose Cancel for long or remote-capable operations. A local crop should normally finish before the 30-second progress-bar threshold; document batches should use page-level progress and cancellation. [GNOME spinner HIG][hig-spinners] [GNOME progress-bar HIG][hig-progress]

### Themes and localization

1. **Recommendation (inferred):** follow system light/dark/high-contrast settings. Draw selection boundaries using more than hue—for example, contrasting inner/outer strokes plus handles and a textual size indicator—and obtain colors from theme variables. Test against both very light and very dark captured content. [GNOME UI styling HIG][hig-styling] [Libadwaita appearance documentation][libadwaita-appearance]
2. **Recommendation (inferred):** mark every app-authored label, accessible name, error, shortcut description and notification string for translation. Display localized language names rather than raw Tesseract codes, preserve recognized text unchanged, and test bidirectional scripts in both the result view and spatial ordering. [GNOME localization practices][gnome-localization] [GNOME writing style][hig-writing]

### Privacy-sensitive capture

1. **Recommendation (inferred):** capture only after an explicit user action and request the smallest portal target available. Never start a silent recurring full-desktop capture as a side effect of opening the application. [Screenshot portal contract][portal-screenshot]
2. **Recommendation (inferred):** keep image pixels in memory where possible. If the portal returns a file URI, load it and delete it on every terminal path, including OCR failure and cancellation; make cleanup testable. NormCap, Frog, gImageReader source, and the GNOME extension provide partial or complete precedents. [NormCap portal handler][normcap-portal] [Frog screenshot service][frog-screenshot] [gImageReader GTK capture source][gimagereader-gtk-capture] [GNOME extension processor][gnome-ocr-processor]
3. **Recommendation (inferred):** make local OCR the default and state it plainly. Do not send images or recognized text to telemetry. If cloud OCR/upload is added, require a separate explicit action and destination disclosure before transfer. Default-on action telemetry, model downloads, and upload features should not be conflated with local OCR. [Frog telemetry service][frog-telemetry] [ApexShot OCR fallback][apexshot-ocrs]
4. **Recommendation (inferred):** copy only after successful recognition, disclose the clipboard action, and make persistent history opt-in with clear/delete controls and a retention setting. Make “Clear history” reversible with an Undo toast; if reversal is impossible, confirm the scope before deletion. dpScreenOCR’s useful history also illustrates why recognized text is sensitive stored data. [dpScreenOCR manual][dpscreenocr-manual] [GNOME dialog HIG][hig-dialogs] [GNOME toast HIG][hig-toasts]
5. **Recommendation (inferred):** treat PDF import as a separate trust boundary. If added, isolate processing and surface encryption, signature, malformed-file and unsupported-format errors rather than passing arbitrary documents through the screenshot OCR path. [OCRmyPDF security docs][ocrmypdf-security] [OCRmyPDF errors][ocrmypdf-errors]

## Acceptance evidence the new product should publish

These are inferred verification targets derived from the official guidance and observed landscape gaps:

- Complete a region capture, copy a chosen recognized block, retry a no-text result, and cancel using only the keyboard. [GNOME keyboard HIG][hig-keyboard]
- Repeat the complete flow with Orca and the display off; verify accessible names, roles, selection state, reading order, status announcements and focus restoration. [GNOME accessibility HIG][hig-accessibility] [GTK accessibility documentation][gtk-accessibility]
- Exercise GTK/Libadwaita light, dark, dark-high-contrast, light-high-contrast, large text and on-screen keyboard modes; verify that overlay geometry does not depend on color alone. [GNOME accessibility HIG][hig-accessibility] [Libadwaita appearance documentation][libadwaita-appearance]
- Test Screenshot portal v2 and v3, an unavailable portal, an empty GlobalShortcuts binding result, user cancellation, denial, and portal-returned file cleanup. [Screenshot portal contract][portal-screenshot] [GlobalShortcuts portal contract][portal-global-shortcuts] [Portal request lifecycle][portal-requests]
- Verify that logs, crash reports, telemetry, notifications and persistent settings contain neither captured pixels nor recognized text by default. This is an inferred privacy test, not a direct GNOME requirement.
- Verify translatable strings, localized OCR-language names, right-to-left UI, mixed-direction recognized text, and no hardcoded line breaks. [GNOME localization practices][gnome-localization]

## Landscape gaps and implications

- **Spatial interaction gap:** gImageReader proves that OCR regions and structured text can be connected, but no surveyed screenshot tool provides a documented, accessible, keyboard-navigable word/block overlay comparable to modern “Live Text.” [gImageReader README][gimagereader-readme]
- **Cross-desktop accessibility gap:** portal-backed tools gain desktop-native selection but publish no end-to-end AT guarantees; custom overlays add geometry control but require their own focus and semantic implementation. [GTK accessibility documentation][gtk-accessibility] [Screenshot portal contract][portal-screenshot]
- **GNOME integration gap:** a Shell extension can integrate most directly and support GNOME 45–50, but private internals, extension lifecycle, hardcoded strings and icon-only controls are poor foundations for a durable standalone GTK product. [GNOME extension metadata][gnome-ocr-metadata] [GNOME extension source][gnome-ocr-extension]
- **Maintenance/package gap:** current source and latest packaged release often diverge. gImageReader’s portal code is current-source evidence while its latest release predates the inspected commit by more than a year; NormCap also has current source but an older release. Product decisions should validate behavior in the actual target package, not only repository head. [gImageReader commit][gimagereader-commit] [gImageReader release][gimagereader-release] [NormCap commit][normcap-commit] [NormCap release][normcap-release]
- **Error-model gap:** most screenshot tools present a small number of generic messages. OCRmyPDF’s explicit typed outcomes and the GNOME extension’s cancellation/no-text/missing-engine split are better starting points for a robust GUI contract. [OCRmyPDF exit codes][ocrmypdf-exit-codes] [GNOME extension source][gnome-ocr-extension]
- **Privacy gap:** several projects correctly delete capture files, but persistent text history, default-on telemetry, full-screen-before-crop capture, model downloads, and notification previews show that “OCR runs locally” is not a complete privacy statement. [dpScreenOCR manual][dpscreenocr-manual] [Frog telemetry service][frog-telemetry] [NormCap portal handler][normcap-portal] [ApexShot OCR fallback][apexshot-ocrs] [GNOME extension source][gnome-ocr-extension]

## Source quality and limitations

- **High confidence:** stack, license, source-level capture paths, explicit keyboard handlers, release/commit dates, and GNOME/GTK/portal contracts. These come from pinned project files, first-party release records, and official platform documentation.
- **Moderate confidence:** packaging availability and current runtime behavior. Project READMEs can lag distribution state, and source head can contain behavior not yet present in the latest release.
- **Low/unknown confidence:** runtime compositor compatibility, exact assistive-technology behavior, focus restoration, and high-contrast rendering. No hands-on matrix or published app-level acceptance evidence was available in the inspected sources.
- A recent commit or release is evidence of activity only; it is not evidence of long-term support, security response, package freshness, or feature stability. Conversely, absence of accessibility documentation is not proof that toolkit-default semantics fail.

## Primary source references

[normcap-readme]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/README.md
[normcap-pyproject]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/pyproject.toml
[normcap-screenshot-main]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/screenshot/main.py
[normcap-portal]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/screenshot/handlers/dbus_portal.py
[normcap-grim]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/screenshot/handlers/grim.py
[normcap-gui]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/gui/window.py
[normcap-notifications]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/normcap/gui/notification_utils.py
[normcap-license]: https://github.com/dynobo/normcap/blob/08bd57ed5124779a259876835ecd00f468add421/LICENSE
[normcap-commit]: https://github.com/dynobo/normcap/commit/08bd57ed5124779a259876835ecd00f468add421
[normcap-release]: https://github.com/dynobo/normcap/releases/tag/v0.6.0

[textsnatcher-readme]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/README.md
[textsnatcher-meson]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/src/meson.build
[textsnatcher-app]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/src/Application.vala
[textsnatcher-tesseract]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/src/services/TesseractTrigger.vala
[textsnatcher-home]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/src/screens/HomeScreen.vala
[textsnatcher-select]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/src/screens/SelectPictureScreen.vala
[textsnatcher-main-screen]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/src/screens/MainScreen.vala
[textsnatcher-license]: https://github.com/RajSolai/TextSnatcher/blob/1d7e059e3639acf42db05f20e33ba75a6b9b8b23/LICENSE
[textsnatcher-commit]: https://github.com/RajSolai/TextSnatcher/commit/1d7e059e3639acf42db05f20e33ba75a6b9b8b23
[textsnatcher-releases]: https://github.com/RajSolai/TextSnatcher/releases/tag/v2.0.0

[frog-readme]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/README.md
[frog-meson]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/meson.build
[frog-main]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/frog/main.py
[frog-window]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/frog/window.py
[frog-screenshot]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/frog/services/screenshot_service.py
[frog-telemetry]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/frog/services/telemetry.py
[frog-tts]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/frog/services/tts.py
[frog-share]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/frog/services/share_service.py
[frog-settings-schema]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/data/com.github.tenderowl.frog.gschema.xml
[frog-flatpak]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/flatpak/com.github.tenderowl.frog.json
[frog-translations]: https://github.com/TenderOwl/Frog/tree/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/po
[frog-license]: https://github.com/TenderOwl/Frog/blob/40ea293327fc574e9a5be9e6010c5fa7e9d842a6/LICENSE
[frog-commit]: https://github.com/TenderOwl/Frog/commit/40ea293327fc574e9a5be9e6010c5fa7e9d842a6
[frog-release]: https://github.com/TenderOwl/Frog/releases/tag/1.6.0

[gimagereader-readme]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/README.md
[gimagereader-cmake]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/CMakeLists.txt
[gimagereader-gtk-capture]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/gtk/src/SourceManager.cc
[gimagereader-qt-capture]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/qt/src/SourceManager.cc
[gimagereader-gtk-displayer]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/gtk/src/Displayer.cc
[gimagereader-qt-displayer]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/qt/src/Displayer.cc
[gimagereader-license]: https://github.com/manisandro/gImageReader/blob/046641b8944986bdbb9f3ed4d3dce68a1c26d5de/COPYING
[gimagereader-commit]: https://github.com/manisandro/gImageReader/commit/046641b8944986bdbb9f3ed4d3dce68a1c26d5de
[gimagereader-release]: https://github.com/manisandro/gImageReader/releases/tag/v3.4.3

[dpscreenocr-manual]: https://github.com/danpla/dpscreenocr/blob/058671e473a297c62137202efa2f94a840af7d4f/doc/manual.md
[dpscreenocr-cmake]: https://github.com/danpla/dpscreenocr/blob/058671e473a297c62137202efa2f94a840af7d4f/CMakeLists.txt
[dpscreenocr-license]: https://github.com/danpla/dpscreenocr/blob/058671e473a297c62137202efa2f94a840af7d4f/LICENSE.txt
[dpscreenocr-commit]: https://github.com/danpla/dpscreenocr/commit/058671e473a297c62137202efa2f94a840af7d4f
[dpscreenocr-release]: https://github.com/danpla/dpscreenocr/releases/tag/v1.5.1

[ocrmypdf-intro]: https://ocrmypdf.readthedocs.io/en/stable/introduction.html
[ocrmypdf-install]: https://ocrmypdf.readthedocs.io/en/stable/installation.html
[ocrmypdf-docker]: https://ocrmypdf.readthedocs.io/en/stable/docker.html
[ocrmypdf-api]: https://ocrmypdf.readthedocs.io/en/stable/api.html
[ocrmypdf-architecture]: https://ocrmypdf.readthedocs.io/en/stable/advanced.html
[ocrmypdf-errors]: https://ocrmypdf.readthedocs.io/en/stable/errors.html
[ocrmypdf-security]: https://ocrmypdf.readthedocs.io/en/stable/pdfsecurity.html
[ocrmypdf-exit-codes]: https://github.com/ocrmypdf/OCRmyPDF/blob/cf0df3da06aef04fe9a5bf91c6feff36370bb3eb/src/ocrmypdf/exceptions.py
[ocrmypdf-license]: https://github.com/ocrmypdf/OCRmyPDF/blob/cf0df3da06aef04fe9a5bf91c6feff36370bb3eb/LICENSE
[ocrmypdf-commit]: https://github.com/ocrmypdf/OCRmyPDF/commit/cf0df3da06aef04fe9a5bf91c6feff36370bb3eb
[ocrmypdf-release]: https://github.com/ocrmypdf/OCRmyPDF/releases/tag/v17.13.0

[apexshot-readme]: https://github.com/apex-shot/apexshot/blob/1b30ab1af9c09b0aca6e6de1dd54ec9d7ac5df80/README.md
[apexshot-cargo]: https://github.com/apex-shot/apexshot/blob/1b30ab1af9c09b0aca6e6de1dd54ec9d7ac5df80/Cargo.toml
[apexshot-wayland]: https://github.com/apex-shot/apexshot/blob/1b30ab1af9c09b0aca6e6de1dd54ec9d7ac5df80/src/backend/wayland.rs
[apexshot-overlay-events]: https://github.com/apex-shot/apexshot/blob/1b30ab1af9c09b0aca6e6de1dd54ec9d7ac5df80/capture-overlay/src/CaptureOverlay_Events.cpp
[apexshot-ocrs]: https://github.com/apex-shot/apexshot/blob/1b30ab1af9c09b0aca6e6de1dd54ec9d7ac5df80/src/ocr/ocrs_engine.rs
[apexshot-commit]: https://github.com/apex-shot/apexshot/commit/1b30ab1af9c09b0aca6e6de1dd54ec9d7ac5df80
[apexshot-release]: https://github.com/apex-shot/apexshot/releases/tag/v0.2.35

[spectacle-readme]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/README.md
[spectacle-root-cmake]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/CMakeLists.txt
[spectacle-cmake]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/src/CMakeLists.txt
[spectacle-appdata]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/desktop/org.kde.spectacle.appdata.xml
[spectacle-kwin]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/src/Platforms/ImagePlatformKWin.cpp
[spectacle-selection]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/src/Gui/SelectionEditor.cpp
[spectacle-ocr]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/src/OcrManager.cpp
[spectacle-ocr-action]: https://github.com/KDE/spectacle/blob/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/src/Gui/OcrAction.qml
[spectacle-licenses]: https://github.com/KDE/spectacle/tree/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2/LICENSES
[spectacle-plasma-66]: https://kde.org/announcements/plasma/6/6.6.0/
[spectacle-app-page]: https://apps.kde.org/spectacle/
[spectacle-commit]: https://github.com/KDE/spectacle/commit/5693aaf894bb194c639e3f58e0d1df4c1e82cbb2

[gnome-ocr-readme]: https://github.com/oreocapybara/gnome-native-screenshot-ui-ocr-extended/blob/bccf01bd01e55310cc0fa84da27786e588add293/README.md
[gnome-ocr-metadata]: https://github.com/oreocapybara/gnome-native-screenshot-ui-ocr-extended/blob/bccf01bd01e55310cc0fa84da27786e588add293/metadata.json
[gnome-ocr-extension]: https://github.com/oreocapybara/gnome-native-screenshot-ui-ocr-extended/blob/bccf01bd01e55310cc0fa84da27786e588add293/extension.js
[gnome-ocr-processor]: https://github.com/oreocapybara/gnome-native-screenshot-ui-ocr-extended/blob/bccf01bd01e55310cc0fa84da27786e588add293/ocrProcessor.js
[gnome-ocr-ego]: https://extensions.gnome.org/extension/10254/native-screenshot-ui-ocr-extended/
[gnome-ocr-commit]: https://github.com/oreocapybara/gnome-native-screenshot-ui-ocr-extended/commit/bccf01bd01e55310cc0fa84da27786e588add293
[gnome-ocr-release]: https://github.com/oreocapybara/gnome-native-screenshot-ui-ocr-extended/releases/tag/v0.1.2

[hig-keyboard]: https://developer.gnome.org/hig/guidelines/keyboard.html
[hig-standard-shortcuts]: https://developer.gnome.org/hig/reference/keyboard.html
[hig-pointer]: https://developer.gnome.org/hig/guidelines/pointer-touch.html
[hig-accessibility]: https://developer.gnome.org/hig/guidelines/accessibility.html
[hig-dialogs]: https://developer.gnome.org/hig/patterns/feedback/dialogs.html
[hig-toasts]: https://developer.gnome.org/hig/patterns/feedback/toasts.html
[hig-banners]: https://developer.gnome.org/hig/patterns/feedback/banners.html
[hig-buttons]: https://developer.gnome.org/hig/patterns/controls/buttons.html
[hig-notifications]: https://developer.gnome.org/hig/patterns/feedback/notifications.html
[hig-spinners]: https://developer.gnome.org/hig/patterns/feedback/spinners.html
[hig-progress]: https://developer.gnome.org/hig/patterns/feedback/progress-bars.html
[hig-styling]: https://developer.gnome.org/hig/guidelines/ui-styling.html
[hig-writing]: https://developer.gnome.org/hig/guidelines/writing-style.html
[gnome-localization]: https://developer.gnome.org/documentation/guidelines/localization/practices.html
[gtk-accessibility]: https://docs.gtk.org/gtk4/section-accessibility.html
[gtk-announce]: https://docs.gtk.org/gtk4/method.Accessible.announce.html
[gtk-input]: https://docs.gtk.org/gtk4/input-handling.html
[libadwaita-appearance]: https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/styles-and-appearance.html
[portal-screenshot]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Screenshot.html
[portal-global-shortcuts]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
[portal-requests]: https://flatpak.github.io/xdg-desktop-portal/docs/requests.html
