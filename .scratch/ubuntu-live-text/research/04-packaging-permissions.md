# Packaging, permissions, and model distribution for Kiriglyph

Target: Ubuntu 24.04 LTS, GNOME 46, default Wayland session  
Scope: Debian packages, Flatpak/Flathub, Snap, and AppImage. Sources are primary project documentation, specifications, source/release notes, package metadata, and archive policy.

## Decision

Use a staged, two-track packaging strategy:

1. **Developer and feasibility work:** run native builds and produce a local `.deb` so portal, PipeWire, AppArmor, shared-library, and Ubuntu 24.04 behavior can be debugged without a container boundary. This artifact is not the privacy claim.
2. **User alpha:** publish a **GPG-signed, self-hosted Flatpak repository**. Build from pinned source, bundle the English model, omit network and broad filesystem permissions, and exercise the production sandbox early. Flathub does not accept a new app directly into beta and does not accept nightly software, so it is not the first alpha channel.[Flathub requirements][flathub-requirements]
3. **Open-source 1.0:** make a **Flathub Flatpak** the primary upstream artifact. GNOME calls Flatpak its preferred distribution framework, Flathub builds from public manifests without build-time network, and Flatpak can enforce the local-only claim by giving the app neither network nor general host-file access.[GNOME Flatpak][gnome-flatpak] [Flatpak sandbox][flatpak-sandbox] [Flathub safety][flathub-safety]
4. **Ubuntu/Debian upstreaming after 1.0:** maintain a separate Debian source package, target Debian unstable first, then Ubuntu `universe`. Ubuntu explicitly prefers new packages to enter through Debian.[Ubuntu new packages][ubuntu-new-packages] A future `main` promotion or default installation is a separate, substantially higher bar.

Keep Snap as a possible Ubuntu-specific secondary channel only after a strict-confinement proof on stock 24.04. Do not make AppImage a supported 1.0 channel.

The package format does **not** solve global invocation on the target desktop. Ubuntu 24.04 ships `xdg-desktop-portal` 1.18.x and the GNOME 46 portal backend; the GNOME backend did not add Global Shortcuts until GNOME 48.[Ubuntu portal frontend][ubuntu-portal-frontend] [Ubuntu GNOME portal backend][ubuntu-portals] [GNOME portal 46/48 NEWS][gnome-portal-news] Therefore 24.04 needs an explicit, documented GNOME **Custom Shortcut** whose command activates the app's capture action. Ubuntu documents this user-controlled flow.[Ubuntu custom shortcuts][ubuntu-custom-shortcuts] Do not write the user's dconf settings, grab private GNOME Shell APIs, or install a Shell extension merely to avoid that one-time setup.

## Privacy and permission baseline

The release is trustworthy only if all of these are true:

- Capture always goes through `org.freedesktop.portal.Screenshot` or `org.freedesktop.portal.ScreenCast`; no private Mutter/GNOME Shell capture API and no legacy screen-capture interface.
- The app is launched by an explicit user action. It does not continuously observe the screen and does not capture from an idle background process.
- If ScreenCast is required, request `persist_mode=0`, do not retain a restore token, consume one frame, and close the portal session. The portal supports longer-lived and persistent grants, but those weaken the product's “choose now, capture now” permission story.[ScreenCast portal][portal-screencast]
- The app has **no runtime network permission**. Package-manager traffic for installation and signed updates is outside the app process and cannot contain captured pixels or OCR text.
- Image-file input uses the File Chooser portal. The chosen file is the grant; the app does not receive blanket home, Pictures, Downloads, or removable-media access.[Flatpak file access][flatpak-file-access] [Snap portals][snap-portals]
- Models are installed as authenticated package content. There is no first-run or on-demand model downloader.
- No capture pixels, crops, OCR text, thumbnails, or debug dumps are written outside private temporary memory/storage unless the user explicitly exports them.
- Autostart is off by default. A launch-on-demand shortcut removes the need for a resident service on Ubuntu 24.04.
- Every distributed model and native dependency is versioned, hashed, licensed, represented in the SBOM, and covered by the security-update process.

These paths undermine that contract and should be rejected:

- Flatpak `--share=network`, `--filesystem=home`, `--filesystem=host*`, unrestricted D-Bus names, or direct PipeWire access.
- Snap `network`, `home`, `removable-media`, `pipewire`, `screencast-legacy`, or `classic` confinement unless a separately reviewed feature proves it is indispensable. The portal needs only the `desktop` interface; Snap's own documentation says direct `pipewire` is for cases where portals are insufficient.[Snap PipeWire][snap-pipewire]
- An unconfined `.deb` presented as technically unable to exfiltrate data. A native package has normal user access unless an enforced AppArmor profile says otherwise.
- AppImage as the privacy-enforcing artifact: AppImage is a portable container format, not a sandbox, and normally leaves the app's home-directory behavior unchanged.[AppImage best practices][appimage-best-practices] [AppImage portable mode][appimage-portable]
- In-app self-update or model download code, even if currently pointed only at project servers.
- Persistent ScreenCast restoration, a hidden always-running capture daemon, silent autostart, or automatic modification of GNOME shortcut settings.

## Portal and invocation constraints common to every format

### Capture

The Screenshot portal returns a URI to a screenshot made accessible to the caller. Current interface documentation exposes screen, window, area, and active-window targets, but applications must inspect the interface `version` and `AvailableTargets`; current documentation must not be mistaken for the older API/backend shipped by 24.04.[Screenshot portal][portal-screenshot] The version-2 `interactive` path is the conservative 24.04 baseline.

ScreenCast follows `CreateSession` → `SelectSources` → `Start` → `OpenPipeWireRemote`. The system normally shows the source chooser at `Start`. The returned PipeWire connection exposes only the approved stream nodes, not the user's general PipeWire graph.[ScreenCast portal][portal-screencast] [Portal PipeWire access][portal-pipewire]

This behavior is packaging-neutral:

- Flatpak can reach portals through its default filtered session bus.
- A strict Snap reaches portals through the auto-connected `desktop` interface.[Snap portals][snap-portals]
- A host `.deb` can use portals and register its stable application ID with the Host Portal Registry before its first portal call.[Host portal registry][host-portal-registry]
- An AppImage can call the same API, but reliable app identity depends on stable desktop integration and launch/cgroup identity that AppImage does not supply by itself.

### Focus and application identity

GNOME permission dialogs are not designed to be raised by an unidentified headless process. The upstream portal issue for shortcut-launched screenshot tools records GNOME rejecting requests with “Only the focused app is allowed to show a system access dialog” when app identification/focus is wrong.[Portal shortcut focus issue][portal-focus]

Consequences:

- Use one stable reverse-DNS app ID consistently for process, D-Bus name, desktop file, Flatpak ID, portal registration, and AppStream metadata.
- The custom shortcut must invoke a capture action that obtains foreground activation and presents a real, focusable surface before requesting capture. A permanently hidden daemon calling Screenshot is not a supported design.
- Pass a valid Wayland parent-window identifier whenever a window exists; portal documentation permits an empty value but explains that the handle lets the compositor correctly place the system dialog.[Portal window identifiers][portal-window]
- Test the exact shortcut → activation → permission-dialog path for every package, not just launch from a terminal.

### Global invocation

`org.freedesktop.portal.GlobalShortcuts` provides session-scoped shortcuts and normally presents a configuration dialog.[Global Shortcuts portal][portal-shortcuts] It is the right eventual API, but it has no GNOME 46 backend on Ubuntu 24.04. The 24.04 contract is therefore:

1. Ship a stable command/action such as `APP_LAUNCHER --capture`.
2. On first run, explain the limitation and link to Ubuntu's Custom Shortcuts settings.
3. Let the user choose the accelerator; GNOME reserves `Super` for system shortcuts and advises apps not to claim it themselves.[GNOME keyboard HIG][gnome-keyboard]
4. Detect GlobalShortcuts at runtime on newer desktops and offer it there, without removing the 24.04 fallback.

The package must not install a GNOME Shell extension, use `org.gnome.Shell.GrabAccelerator`, or mutate the custom-keybinding schema. Those choices create private-API, review, upgrade, and consent problems.

### Background service and autostart

The Background portal lets a sandboxed app request background activity and login autostart, with a user-visible reason and returned `background`/`autostart` decisions.[Background portal][portal-background] Native packages can use XDG autostart desktop files or graphical-session user units; the XDG specification makes a system autostart entry effective after login and allows a user entry to override it.[XDG autostart][xdg-autostart] Snap also supports an app-associated autostart desktop file.[Snap format][snap-format]

None is needed for the 24.04 design. On-demand activation is more private, uses less memory, and avoids the portal focus failure. If later releases add a resident shortcut session:

- make “start at login” an opt-in setting;
- use Background portal for Flatpak;
- use an opt-in user service/XDG autostart entry for `.deb`;
- use Snap's user-session autostart mechanism, not a root/system daemon;
- show running/background state and a single control to disable it;
- keep capture impossible until a fresh shortcut activation.

## Format assessment

### Debian/Ubuntu `.deb`

**Strengths**

- Best developer format for stock-Ubuntu debugging and the only direct route to the Ubuntu archive.
- Uses distro shared libraries, ABI relationships, symbols, and ordinary security updates instead of privately bundled copies. Debian Policy says convenience copies should not be used when the library is already packaged.[Debian source policy][debian-source-policy]
- Ubuntu 24.04 already contains `libtesseract5`, `tesseract-ocr`, and `tesseract-ocr-eng` in `universe`; the English data package is architecture-independent and about 4 MB installed.[Ubuntu Tesseract packages][ubuntu-tesseract]
- Large architecture-independent model data can be split into an `Architecture: all` package, which Debian recommends for substantial shared data.[Debian packaging practices][debian-practices]
- APT authenticates a signed `InRelease`/`Release` index and follows hashes through `Packages` to each `.deb`; official Debian does not rely on individual `.deb` signatures.[APT secure][apt-secure]
- Debian Policy requires reproducible builds as a “should”; Debian emits build information, and `SOURCE_DATE_EPOCH` is integrated into its toolchain.[Debian source policy][debian-source-policy] [SOURCE_DATE_EPOCH][source-date-epoch]

**Weaknesses and permission experience**

- There is no sandbox by default. The app can ordinarily read the user's files and open network sockets without a runtime prompt.
- Portal capture still gives a good GNOME chooser, but filesystem and network access outside portals are governed only by Unix permissions unless confinement is added.
- XDG autostart or a user service has no standardized install-time permission dialog. Shipping it enabled would be a trust regression.
- A manually downloaded `.deb` does not gain APT's archive trust chain merely by being a `.deb`. Alpha distribution should use a signed PPA/repository or separately signed checksums, not an unsigned release attachment. Launchpad can source-build Git recipes into a PPA and its signing service signs archive metadata.[Launchpad source recipes][launchpad-recipes] [Launchpad signing service][launchpad-signing]

**Required native confinement**

For a 1.0 PPA or direct `.deb`, ship an enforcing AppArmor profile:

- deny network;
- allow only the app's private config/cache/state, required system libraries, Wayland/session D-Bus, portal calls, and portal-returned document paths;
- keep OCR workers in the same or a stricter child profile;
- verify the profile in automated tests on 24.04.

Debian provides `dh_apparmor` for packages to install/reload a profile, and Ubuntu documents AppArmor as kernel-enforced application policy.[Debian AppArmor packaging][debian-apparmor] [Ubuntu AppArmor][ubuntu-apparmor] This narrows the gap with Flatpak, but maintaining D-Bus and dynamically mediated document rules is extra work. Until that profile is enforced and tested, the native package must be described as “local by implementation,” not “network-impossible.”

**Models and updates**

- Prefer an existing distro language-data package when its quality is sufficient.
- Put a custom model in a separate, version-locked `Architecture: all` binary package built from the same reviewed source package or a clearly related source package.
- Never fetch the model in `postinst` or first run.
- A model update is an APT package update with a new version, hash, changelog, license record, and SBOM.

**Archive fit**

`universe` is realistic after 1.0 if every file is redistributable, the source build is offline, embedded libraries are removed, and a maintainer is available. `main` is not a near-term target: Ubuntu requires all runtime code/dependencies to be in `main`, a non-trivial test suite, maintainership, and security review; even Tesseract is currently in `universe`.[Ubuntu archive][ubuntu-archive] [Ubuntu MIR][ubuntu-mir]

### Flatpak / Flathub

**Strengths**

- Best match for the strict local privacy contract. By default a Flatpak has no host-file, network, device, outside-process, broad session-bus, X11, or system-bus access.[Flatpak sandbox][flatpak-sandbox]
- Portals provide selected-file and screenshot/screencast access without static host filesystem grants.
- GNOME explicitly recommends Flatpak; GNOME Circle requires applications to be installable as Flatpaks and to use the GNOME platform including GTK.[GNOME Flatpak][gnome-flatpak] [GNOME Circle criteria][gnome-circle]
- The desktop file, icon, AppStream metadata, app ID, and sandbox are one reviewed unit.
- Flathub requires minimal static permissions, source builds, declared sources, checksums/pinned commits, and no build network. Official builds are signed and Flatpak/OSTree verifies them.[Flathub requirements][flathub-requirements] [Flathub safety][flathub-safety]
- OSTree versioning deduplicates files, supports rollback, and sends deltas; this is well suited to large but slowly changing model assets.[Flatpak internals][flatpak-internals] [Flatpak repositories][flatpak-repositories]

**Required manifest posture**

The production manifest should normally need only:

- Wayland display access;
- GPU/D-Bus permissions required by the chosen toolkit, kept to Flathub's documented minimum;
- portal access already available through Flatpak's filtered bus;
- no network share;
- no `home`, `host`, Pictures, Downloads, removable-media, or direct PipeWire permission;
- no fallback X11 if the supported target is explicitly GNOME Wayland, unless accessibility/compatibility testing proves it necessary.

The app's mutable data remains under its private Flatpak directory. Input files come from FileChooser; capture comes from Screenshot/ScreenCast.

**Native libraries**

Use the current GNOME runtime for GTK/libadwaita components and build OCR/inference libraries as pinned manifest modules when the runtime does not contain them. Flathub requires all source-available dependencies to build from source and disallows undeclared build-time downloads and precompiled files in the submission.[Flathub requirements][flathub-requirements] This is feasible for Tesseract and ONNX Runtime but may make a full PaddlePaddle or ad-hoc Flutter/prebuilt-engine stack expensive or unacceptable until a source-complete, offline build is proven. Flathub's CI has finite CPU, memory, and time; unusually large builds need review/external runners.[Flathub maintenance][flathub-maintenance]

**Models and updates**

- Include the default English model as a pinned, SHA-256-verified manifest source and install it read-only under `/app`.
- If future language packs are optional and large, define an app-specific Flatpak extension. Flatpak extensions are independently installable branches mounted into an app-defined extension point.[Flatpak extensions][flatpak-extensions]
- Keep the default model in the signed app/extension commit; use Flathub `extra-data` only if redistribution or repository-size rules require it. Flathub says `extra-data` reduces auditability and multi-architecture support, so it is a last resort.[Flathub safety][flathub-safety]
- Model installation/update must never require `--share=network` for the app.

**Channels and reproducibility**

- A self-hosted alpha repository can use signed refs/branches and static deltas. Every repository commit should be GPG-signed.[Flatpak signing][flatpak-signing]
- Flathub has only stable and beta app channels; beta is available only after initial stable acceptance and is not for permanent/nightly delivery.[Flathub maintenance][flathub-maintenance]
- Flathub publishes the processed manifest in `/app/manifest.json`, mirrors build sources, records runtime/SDK commits, and documents how to rebuild. That is strong auditability, but still run an independent byte-for-byte reproducibility job rather than treating a manifest as proof.[Flathub rebuilding][flathub-rebuilding]

**Blockers**

- GNOME 46 lacks the GlobalShortcuts backend, so Flatpak cannot provide automatic global invocation on the target OS.
- Portal focus/identity must work when invoked by the custom shortcut.
- The build must be source-complete and network-free, including OCR runtime and any UI engine.
- Flathub will reject broad permissions, EOL runtimes, insecure configuration, or unpinned/unavailable sources.
- Do not use `org.gnome.*` unless accepted/authorized by GNOME; Flathub protects that namespace.[Flathub requirements][flathub-requirements]

### Snap

**Strengths**

- Native Ubuntu Store and desktop integration, with `edge`, `beta`, `candidate`, and `stable` risks plus optional tracks/branches.[Snap channels][snap-channels]
- Strict confinement generates AppArmor, seccomp, namespace, and device-cgroup policy from declared interfaces.[Snap security][snap-security]
- The `desktop` interface is auto-connected and gives access to XDG portals. Official Snap guidance recommends portals for screenshots, screencasts, and selected files.[Snap portals][snap-portals]
- The Store signs assertions and hashes artifacts; installed snaps are read-only SquashFS. Store refreshes generate binary deltas automatically.[Snap assertions][snap-assertions] [Snap deltas][snap-deltas]
- Native libraries can be staged from the Ubuntu base/archive or built into the snap. Optional snap components/content snaps can separate large model resources.[Snap components][snap-components]

**Required plugs and confinement**

Use `confinement: strict`; declare `desktop` and the minimum display/rendering plugs only. Omit `network`, `home`, `removable-media`, `personal-files`, `pipewire`, and `screencast-legacy`. Snap recommends FileChooser over `home`/`removable-media` because the portal grants only the user-selected file.[Snap filesystem access][snap-files]

Do not request classic confinement. Canonical describes it as equivalent to traditional unrestricted access, requires `--classic`, and subjects Store publication to special review.[Snap classic][snap-classic] It would erase Snap's main privacy advantage.

**Caveats**

- Auto-connected interfaces do not produce a runtime prompt. The Store policy and `snap connections` expose them, so the manifest must remain minimal.
- Snap desktop files may be name-mangled; preserving exact desktop IDs requires newer snapd support, and Snap strips unsupported desktop keys including `DBusActivatable`.[Snap format][snap-format] Stable portal identity and shortcut focus need a stock-24.04 test.
- An upstream Snap issue shows a 24.04 screenshot app failing GNOME's focused-app access-dialog check while its source/Flatpak builds did not. That is not proof all Snaps fail, but it is a release blocker that must be tested for this app.[Snap screenshot focus report][snap-focus]
- Snap autostart exists, and user services add lifecycle complexity. Neither is needed for launch-on-demand.
- Store assertions prove origin/integrity, not source equivalence. Snapcraft documentation does not provide a native bit-for-bit reproducibility or complete SBOM guarantee; CI must add both.
- Components are useful for optional resources, but add snapd-version, Store, test, and lifecycle complexity. Bundle the English model in the first Snap unless its size makes that untenable.

**Recommendation**

Snap is a credible second 1.x channel for Ubuntu users if strict confinement, stable app identity, portal capture, custom-shortcut launch, and focus all pass on a clean 24.04 image. It is not the primary upstream/GNOME artifact and it does not advance Ubuntu archive eligibility.

### AppImage

**Strengths**

- Easy single-file trial artifact.
- Can bundle nearly all native libraries and models.
- Supports optional embedded GPG signatures and optional zsync-style differential updates.[AppImage signatures][appimage-signatures] [AppImage updates][appimage-updates]
- Can call host portals if correctly integrated and identified.

**Failures for this product**

- AppImage is not a sandbox or package policy system. The payload retains ordinary user filesystem and network access.
- Desktop integration, menu registration, update handling, and removal require optional tools such as `appimaged` or AppImageLauncher.[AppImage integration][appimage-integration] Without integration, stable portal identity and a durable custom-shortcut command are poor.
- Type-2 AppImages rely on FUSE; official documentation calls out Ubuntu 24.04's `libfuse2t64` rename and extract-and-run fallback.[AppImage FUSE][appimage-fuse]
- Native-library compatibility is the publisher's burden: build on the oldest target and bundle most non-base libraries, while avoiding incompatible low-level libraries.[AppImage best practices][appimage-best-practices]
- Embedded signatures are optional and need an external verifier; the runtime itself performs no signature check.[AppImage signatures][appimage-signatures]
- AppImageUpdate verifies update integrity, but its documentation still distinguishes that from signature validation.[AppImage updates][appimage-updates]
- The format is not a build system and gives no reproducibility guarantee. Open Build Service can make a controlled build, but that is an external discipline.[AppImage reproducibility][appimage-reproducibility]
- Bundled models enlarge every image; model separation loses the single authenticated unit unless the project invents another signed repository.
- It offers no route to Flathub, GNOME Circle, Debian, or the Ubuntu archive.

**Recommendation**

Do not publish AppImage as an official alpha or 1.0 artifact. At most, use it as an explicitly unsupported developer demo after the Flatpak and `.deb` paths work. Calling an AppImage “offline/private” without a sandbox would overstate what the package enforces.

## User-visible permission and setup experience

### Expected

1. **Install/update**
   - Flatpak: repository trust plus reviewed static permissions; the app itself has no network.
   - Snap: Store trust and declared interfaces; `desktop` is auto-connected.
   - APT: adding a PPA/repository is a high-trust action; APT verifies signed archive metadata.
2. **First run on Ubuntu 24.04**
   - Explain that GNOME 46 lacks the global-shortcut portal.
   - Offer the exact capture command and steps for Settings → Keyboard → Custom Shortcuts.
   - Do not ask for background/autostart.
3. **Capture**
   - The shortcut foreground-activates the app.
   - GNOME's portal UI asks the user to select/confirm the area, window, or monitor.
   - Cancel returns to the prior state with no capture retained.
4. **Open image**
   - The native file chooser appears; choosing a file is the permission grant.
5. **Future GNOME with GlobalShortcuts**
   - The portal shows a shortcut configuration dialog controlled by the desktop.

### Not expected

- No root/polkit prompt for ordinary use.
- No filesystem, camera, microphone, accessibility, input-injection, or network permission.
- No prompt to install/download a model on first use.
- No “allow forever” screen-capture flow on 24.04.
- No tray icon or unexplained background process.

## Model and dependency license due diligence

The app's license cannot legalize its dependencies or weights. Treat each model as a separately reviewed release artifact.

### Candidate status

**Tesseract**

- Tesseract code is Apache-2.0; upstream notes that Leptonica is essentially BSD-2-Clause.[Tesseract repository][tesseract]
- `tessdata_fast` and `tessdata_best` explicitly state that all repository data is Apache-2.0.[tessdata_fast][tessdata-fast] [tessdata_best][tessdata-best]
- Ubuntu 24.04 and Debian already distribute the engine and language data, giving the clearest archive precedent.
- Still pin the exact traineddata tag/commit and hash; preserve Apache license/NOTICE obligations and the package's copyright metadata.

**PaddleOCR / PaddlePaddle**

- PaddleOCR and PaddlePaddle repositories use Apache-2.0. In an upstream PaddleOCR issue, a maintainer states that the named PP-OCRv3 detection/recognition/classification weights are Apache-2.0.[PaddleOCR license][paddleocr-license] [PaddleOCR model answer][paddleocr-model-license] [Paddle license][paddle-license]
- That answer covers named artifacts, not every future model URL, derivative, dataset, or third-party runtime component. PaddlePaddle carries a large third-party dependency graph.
- Before redistribution, capture the exact model URL, immutable hash, model name/version, repository license at that revision, maintainer statement, training-data/model-card provenance, conversion script, and all third-party notices.
- Full PaddlePaddle is a difficult Debian/Flathub dependency because of build size and vendored code. An ONNX export may improve packaging but does not erase the source model's license/provenance.

**ONNX Runtime and ONNX models**

- ONNX Runtime is MIT-licensed and ships a substantial `ThirdPartyNotices.txt`; both must be represented in notices and the SBOM.[ONNX Runtime license][onnxruntime-license] [ONNX Runtime notices][onnxruntime-notices]
- An ONNX file has its own license. Runtime MIT licensing says nothing about model redistribution.
- Debian now packages ONNX Runtime from repacked source, but its copyright metadata excludes `.onnx`, `.ort`, and `.bin` model files with unclear licenses.[Debian ONNX Runtime copyright][debian-onnxruntime] This is direct evidence that an ONNX container is not archive clearance.

**EasyOCR**

- The code repository is Apache-2.0, but the standard flow automatically downloads selected model weights to the user's home directory.[EasyOCR repository][easyocr]
- Do not ship EasyOCR until every exact detector/recognizer weight has an explicit redistributable license and provenance record. Disable its downloader and package the reviewed files. The default downloader conflicts with the no-network/no-first-run-download contract.

### Debian/Ubuntu model-weight blocker

Debian's DFSG requires source and modification rights, but the project has not adopted a simple universal rule for whether weights alone are the preferred form for modifying an ML model. A 2025 proposal that would have declared models without original training data/program non-DFSG was withdrawn.[Debian AI proposal withdrawal][debian-ai-withdrawal] Current Debian packaging nevertheless shows conservative practice: PyTorch excludes pretrained neural networks, and ONNX Runtime excludes model files with unclear licenses.[Debian PyTorch copyright][debian-pytorch] [Debian ONNX Runtime copyright][debian-onnxruntime]

Therefore:

- **Tesseract language data has the lowest archive risk** because it is already accepted and separately packaged.
- A custom Paddle/EasyOCR/ONNX weight is an **Ubuntu/Debian archive blocker until reviewed by Debian FTP/legal maintainers**, even when upstream labels it Apache-2.0.
- Flatpak or Snap redistribution can proceed only after ordinary copyright/license due diligence; archive acceptance must not be assumed from Store acceptance.

### Required model ledger

For each model release record:

- model name, task, language, upstream project, version/tag/commit;
- original URL and immutable SHA-256;
- shipped format and shipped hash;
- original license, copyright holders, NOTICE, and a copy of the terms;
- model-specific license statement, not just runtime/repository license;
- training and fine-tuning datasets, their licenses/terms, and known provenance gaps;
- training/export/conversion scripts and their versions;
- original-to-shipped transformation command and deterministic output hash;
- expected runtime/opset, architecture independence, and minimum runtime version;
- security contact, update source, end-of-life rule, and replacement/migration behavior.

Any `unknown`, “research only,” non-commercial, no-derivatives, gated-clickthrough, or non-redistributable entry blocks the model from the default package and from GNOME Circle/Ubuntu `main` ambitions.

## SBOM, provenance, reproducibility, and security updates

### Release requirements

For every architecture and package format:

1. Generate an SPDX or CycloneDX SBOM from the **final artifact**, not only language lockfiles.
2. List the app, bundled/statically linked code, shared runtime/base, OCR engine, model files, model hashes, UI engine, generated bindings, and packaging helpers.
3. Represent each model as its own component. CycloneDX explicitly supports machine-learning model components, provenance, licenses, and vulnerabilities.[CycloneDX specification][cyclonedx]
4. Record declared and concluded licenses plus checksums/source locations; SPDX supports package composition, provenance, licensing, and integrity fields.[SPDX specification][spdx]
5. Publish the SBOM beside the artifact and embed a copy in the package's documentation area.
6. Produce signed SLSA-style provenance containing source revision, manifest, build definition, resolved inputs, builder identity, and output hashes. SLSA distinguishes provenance from bit-for-bit reproducibility.[SLSA provenance][slsa]
7. Sign artifacts/repositories and provenance with CI-held release credentials, and test verification from a clean machine.
8. Run two isolated builds with pinned inputs and compare outputs. Reproducible Builds defines the goal as an independently verifiable, byte-identical path from source to binary.[Reproducible Builds][reproducible-builds]

### Format-specific update ownership

- **Debian/Ubuntu:** distro shared libraries can receive coordinated fixes and appear in package security trackers, but `universe` is community-maintained. The project still owns timely fixes for its package, model, AppArmor profile, and any embedded code.
- **Flatpak:** runtime fixes roll out separately to all apps using the runtime. Every library bundled under `/app` and every model remains this project's responsibility; keep the runtime current and rebuild promptly.[Flathub security][flathub-security]
- **Snap:** base-snap fixes can update independently, but staged/bundled libraries and models require a new snap revision. Assertions are not an SBOM.
- **AppImage:** the project owns every bundled component and the entire update path; no distro dependency graph can identify affected files.

Automate monitoring for upstream security advisories, CVEs, EOL runtime/base notices, model revisions, and disappeared/mutated source URLs. Fail the build if a fetched source hash changes. Models may not receive CVEs, so compare exact model hashes and treat any replacement as a security-relevant release.

## Acceptance blockers and release gates

### Before user alpha

- A stable reverse-DNS app ID and desktop integration exist.
- Custom shortcut launch reliably foregrounds the app and opens the portal dialog on a clean 24.04 GNOME Wayland VM.
- Self-hosted Flatpak has no network/broad filesystem permissions and its repository is GPG-signed.
- The English model is bundled, hashed, licensed, and works with networking disabled.
- No autostart/background service is installed.
- SBOM and notices are generated from the final artifact.

### Before 1.0 / Flathub

- Source-only, network-free Flatpak build of the full UI/OCR stack.
- Current supported runtime and minimal linter-clean permissions.
- Stable and accessible portal interaction, including shortcut focus, cancellation, multi-monitor behavior, and cleanup.
- No persistent capture restore token.
- Reproducibility report, signed provenance, SBOM, dependency/model update policy, and security contact.
- AppStream metadata, content rating, screenshots, desktop file, icons, and controlled app ID.
- Exact licenses for all code, models, datasets needed to establish redistribution rights, fonts/test data, and notices.

### Before GNOME Circle

- Flatpak availability, OSI-approved project license, no CLA, GTK/GNOME platform use, desktop integration, and GNOME-quality UI are explicit Circle criteria.[GNOME Circle criteria][gnome-circle]
- A Flutter-first UI that does not use GTK/GNOME platform technology is therefore a likely Circle blocker even if the Flatpak itself works.
- Private GNOME APIs, Shell extensions, forced `Super` shortcuts, broad permissions, or non-native permission dialogs would also work against acceptance.

### Before Debian/Ubuntu archive submission

- Stable source release and complete source package; no build network.
- All licenses and copyrights documented in `debian/copyright`.
- No convenience copies where Debian libraries exist; separately package missing runtime dependencies.
- Models pass redistributability and preferred-form/source review.
- Reproducible builds, tests/autopkgtests, man pages, AppStream/desktop validation, and an enforcing AppArmor profile.
- Separate architecture-independent model data.
- Submit to Debian first; target Ubuntu `universe`.
- Treat `main`/default-installation as a later program requiring dependency promotion, an owning team, MIR, security review, and long-term maintenance.

## Final recommendation

The defensible path is **native/local `.deb` for development → signed self-hosted Flatpak for alpha → Flathub Flatpak for 1.0 → Debian source package for eventual Ubuntu `universe`**.

For Ubuntu 24.04, global invocation must be a user-created GNOME custom shortcut that activates a foreground capture action. Do not add a daemon simply to own a shortcut. Keep ScreenCast non-persistent, omit app network and broad filesystem access, bundle the model, and make capture permission visible through the GNOME portal.

Snap can be added later under strict confinement if the 24.04 portal identity/focus path passes. AppImage and Snap classic confinement are incompatible with an enforceable local-privacy claim and should not be official release paths.

## Sources

[portal-screenshot]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Screenshot.html
[portal-screencast]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html
[portal-pipewire]: https://flatpak.github.io/xdg-desktop-portal/docs/pipewire.html
[portal-shortcuts]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
[portal-background]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Background.html
[portal-window]: https://flatpak.github.io/xdg-desktop-portal/docs/window-identifiers.html
[portal-focus]: https://github.com/flatpak/xdg-desktop-portal/issues/1070
[host-portal-registry]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.host.portal.Registry.html
[ubuntu-portal-frontend]: https://packages.ubuntu.com/en/noble/xdg-desktop-portal
[ubuntu-portals]: https://packages.ubuntu.com/noble/xdg-desktop-portal-gnome
[gnome-portal-news]: https://gitlab.gnome.org/GNOME/xdg-desktop-portal-gnome/-/raw/gnome-48/NEWS
[ubuntu-custom-shortcuts]: https://help.ubuntu.com/stable/ubuntu-help/keyboard-shortcuts-set.html
[gnome-keyboard]: https://developer.gnome.org/hig/guidelines/keyboard.html
[xdg-autostart]: https://specifications.freedesktop.org/autostart/latest/

[flatpak-sandbox]: https://docs.flatpak.org/en/latest/sandbox-permissions.html
[flatpak-file-access]: https://docs.flatpak.org/en/latest/sandbox-permissions.html
[flatpak-internals]: https://docs.flatpak.org/en/latest/under-the-hood.html
[flatpak-repositories]: https://docs.flatpak.org/en/latest/repositories.html
[flatpak-signing]: https://docs.flatpak.org/en/latest/flatpak-builder.html#signing
[flatpak-extensions]: https://docs.flatpak.org/en/latest/extension.html
[flathub-requirements]: https://docs.flathub.org/docs/for-app-authors/requirements
[flathub-safety]: https://docs.flathub.org/blog/app-safety-layered-approach-source-to-user
[flathub-maintenance]: https://docs.flathub.org/docs/for-app-authors/maintenance
[flathub-rebuilding]: https://docs.flathub.org/docs/for-users/rebuilding
[flathub-security]: https://docs.flathub.org/docs/for-app-authors/runtimes
[gnome-flatpak]: https://developer.gnome.org/documentation/introduction/flatpak.html
[gnome-circle]: https://gitlab.gnome.org/Teams/Circle/-/blob/main/README.md

[snap-portals]: https://snapcraft.io/docs/explanation/snap-development/xdg-desktop-portals/
[snap-security]: https://snapcraft.io/docs/explanation/security/security-policies/
[snap-channels]: https://snapcraft.io/docs/explanation/how-snaps-work/channels-and-tracks/
[snap-assertions]: https://snapcraft.io/docs/explanation/security/assertions/
[snap-deltas]: https://snapcraft.io/docs/explanation/how-snaps-work/snap-deltas/
[snap-components]: https://snapcraft.io/docs/explanation/how-snaps-work/snap-components/
[snap-format]: https://snapcraft.io/docs/reference/development/yaml-schemas/the-snap-format/
[snap-files]: https://snapcraft.io/docs/reference/interfaces/home-interface/
[snap-pipewire]: https://snapcraft.io/docs/reference/interfaces/pipewire-interface/
[snap-classic]: https://snapcraft.io/docs/explanation/security/classic-confinement/
[snap-focus]: https://forum.snapcraft.io/t/screenshots-on-gnome-in-snap/47452

[appimage-best-practices]: https://docs.appimage.org/reference/best-practices.html
[appimage-portable]: https://docs.appimage.org/user-guide/portable-mode.html
[appimage-signatures]: https://docs.appimage.org/packaging-guide/optional/signatures.html
[appimage-updates]: https://docs.appimage.org/packaging-guide/optional/updates.html
[appimage-integration]: https://docs.appimage.org/user-guide/run-appimages.html
[appimage-fuse]: https://docs.appimage.org/user-guide/troubleshooting/fuse.html
[appimage-reproducibility]: https://docs.appimage.org/packaging-guide/hosted-services/opensuse-build-service.html

[debian-source-policy]: https://www.debian.org/doc/debian-policy/ch-source
[debian-practices]: https://www.debian.org/doc/manuals/developers-reference/best-pkging-practices.html
[apt-secure]: https://manpages.debian.org/unstable/apt/apt-secure.8.en.html
[source-date-epoch]: https://reproducible-builds.org/docs/source-date-epoch/
[debian-apparmor]: https://manpages.debian.org/unstable/dh-apparmor/dh_apparmor.1.en.html
[ubuntu-apparmor]: https://documentation.ubuntu.com/security/security-features/privilege-restriction/apparmor/
[launchpad-recipes]: https://documentation.ubuntu.com/launchpad/user/how-to/source-package-recipe/
[launchpad-signing]: https://documentation.ubuntu.com/launchpad/developer/reference/services/signing/
[ubuntu-new-packages]: https://documentation.ubuntu.com/project/how-ubuntu-is-made/processes/new-packages/
[ubuntu-archive]: https://ubuntu.com/project/docs/how-ubuntu-is-made/concepts/package-archive/
[ubuntu-mir]: https://ubuntu.com/project/docs/MIR/main-inclusion-review/
[ubuntu-tesseract]: https://packages.ubuntu.com/noble/tesseract-ocr-eng

[tesseract]: https://github.com/tesseract-ocr/tesseract/blob/main/README.md
[tessdata-fast]: https://github.com/tesseract-ocr/tessdata_fast/blob/main/README.md
[tessdata-best]: https://github.com/tesseract-ocr/tessdata_best/blob/main/README.md
[paddleocr-license]: https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE
[paddleocr-model-license]: https://github.com/PaddlePaddle/PaddleOCR/issues/8780
[paddle-license]: https://github.com/PaddlePaddle/Paddle/blob/develop/LICENSE
[onnxruntime-license]: https://github.com/microsoft/onnxruntime/blob/main/LICENSE
[onnxruntime-notices]: https://github.com/microsoft/onnxruntime/blob/main/ThirdPartyNotices.txt
[debian-onnxruntime]: https://metadata.ftp-master.debian.org/changelogs/main/o/onnxruntime/onnxruntime_1.23.2+dfsg-6_copyright
[easyocr]: https://github.com/JaidedAI/EasyOCR/tree/v1.7.0
[debian-ai-withdrawal]: https://lists.debian.org/debian-vote/2025/05/msg00105.html
[debian-pytorch]: https://metadata.ftp-master.debian.org/changelogs/main/p/pytorch/pytorch_2.6.0+dfsg-7_copyright

[spdx]: https://spdx.github.io/spdx-spec/v3.0.1/model/Software/Classes/Sbom/
[cyclonedx]: https://cyclonedx.org/specification/overview/
[slsa]: https://slsa.dev/spec/v1.2/build-provenance
[reproducible-builds]: https://reproducible-builds.org/
