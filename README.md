# Report Template (macOS)

A macOS app built with SwiftUI.

## Install

### Option 1: DMG (recommended)

1. Download `Report-Template-<version>.dmg` from Releases.
2. Open the DMG file.
3. Drag `Report Template.app` into `Applications`.
4. Open the app from `Applications`.

### Option 2: Shell installer

1. Download `Report-Template-<version>-installer.sh` from Releases.
2. Run:

```bash
chmod +x Report-Template-<version>-installer.sh
./Report-Template-<version>-installer.sh
```

The installer copies the app into `/Applications` by default.

## First launch note

If macOS blocks first launch, open with:

1. `Control` + click the app
2. Click `Open`
3. Confirm `Open`

## Build release artifacts

From repo root:

```bash
./scripts/release.sh
```

Artifacts are generated in `dist/`:

- `Report Template.app`
- `Report-Template-<version>.dmg`
- `Report-Template-<version>-installer.sh`

For smooth public distribution, use Apple Developer ID signing and notarization before publishing.
