# macOS Distribution

This project can generate:

- A drag-and-drop DMG (`.dmg`)

## Build release artifacts

Run from repo root:

```bash
chmod +x scripts/release.sh
./scripts/release.sh
```

Artifacts are written to `dist/`:

- `dist/Report Template.app`
- `dist/Report-Template-<version>.dmg`

By default, the script builds for your current Mac architecture only (`arm64` on Apple Silicon, `x86_64` on Intel).  
If you want a universal build, run:

```bash
DESTINATION="generic/platform=macOS" ./scripts/release.sh
```

## How users install

- DMG route (recommended): open the DMG, drag `Report Template.app` into `Applications`.
- Terminal route (optional): run `install.sh` to download latest release DMG and install to `Applications`.

## Important for public release

Current script builds unsigned binaries (`CODE_SIGNING_ALLOWED=NO`), which may show macOS security warnings.
Unsigned `.command` installers are blocked more aggressively by Gatekeeper, which is why DMG is the default distribution format.

Better approach for public distribution:

1. Use Apple Developer ID Application signing.
2. Notarize the app/DMG with Apple.
3. Staple notarization tickets before publishing.
