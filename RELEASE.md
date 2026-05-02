# macOS Distribution

This project can generate:

- A drag-and-drop DMG (`.dmg`)
- A signed Sparkle feed (`appcast.xml`)

Release channels:

- `production`: Developer ID + notarized artifacts for `v*` tags.
- `beta`: unsigned prerelease artifacts for `beta-v*` tags.

## Build release artifacts

Run from repo root:

```bash
chmod +x scripts/release.sh
RELEASE_CHANNEL=beta ./scripts/release.sh
```

Artifacts are written to `dist/`:

- `dist/Report Template.app`
- `dist/Report-Template-<version>.dmg`
- `dist/appcast.xml`

By default, the script builds for your current Mac architecture only (`arm64` on Apple Silicon, `x86_64` on Intel).  
If you want a universal build, run:

```bash
DESTINATION="generic/platform=macOS" ./scripts/release.sh
```

Sparkle release configuration (optional env vars):

```bash
SPARKLE_KEY_ACCOUNT="KarlApp.Report-Template" \
RELEASE_TAG="v1.1.2" \
DOWNLOAD_URL_PREFIX="https://github.com/Karlpogi11/pmg-report/releases/download/v1.1.2/" \
./scripts/release.sh
```

Notes:

- `SPARKLE_KEY_ACCOUNT` is looked up in macOS Keychain for the EdDSA private key used to sign appcast entries.
- In beta mode, `PPUpdatesEnabled` is written as `false` in the built app so in-app Sparkle checks are disabled.
- In local mode, if the key does not exist yet and `SPARKLE_ALLOW_KEY_GENERATION=1`, `scripts/release.sh` can create it.
- The generated `dist/appcast.xml` is also copied to repo root `appcast.xml` by default.

## Beta release behavior (unsigned)

Beta releases are intentionally unsigned/not notarized while production credentials are unavailable.

```bash
RELEASE_CHANNEL=beta \
SPARKLE_ALLOW_KEY_GENERATION=0 \
SPARKLE_PRIVATE_KEY_BASE64="<base64-private-key>" \
RELEASE_TAG="beta-v1.1.6-beta.1" \
DOWNLOAD_URL_PREFIX="https://github.com/Karlpogi11/pmg-report/releases/download/beta-v1.1.6-beta.1/" \
./scripts/release.sh
```

Verification scope in beta mode:

1. App bundle integrity (`codesign --verify`).
2. DMG integrity (`hdiutil verify`).
3. Sparkle appcast signature presence and expected DMG reference.

## Production signing and notarization

For public macOS distribution, use Developer ID signing and notarization.

1. Create a notarytool keychain profile once:

```bash
xcrun notarytool store-credentials "karlapp-notary" \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "app-specific-password"
```

2. Run the release script with signing identity + notary profile:

```bash
RELEASE_CHANNEL=production \
PRODUCTION_RELEASE=1 \
DEVELOPER_ID_APP_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
NOTARY_KEYCHAIN_PROFILE="karlapp-notary" \
NOTARY_TEAM_ID="ABCDE12345" \
SPARKLE_KEY_ACCOUNT="KarlApp.Report-Template" \
SPARKLE_ALLOW_KEY_GENERATION=0 \
RELEASE_TAG="v1.1.2" \
DOWNLOAD_URL_PREFIX="https://github.com/Karlpogi11/pmg-report/releases/download/v1.1.2/" \
./scripts/release.sh
```

What the script now does in this mode:

1. Builds app with Xcode.
2. Signs app in `dist/` with Developer ID Application + hardened runtime.
3. Notarizes app and staples ticket.
4. Creates DMG, signs DMG, notarizes DMG, staples ticket.
5. Generates Sparkle appcast from the final notarized DMG.
6. Runs verification gates (codesign validation, DMG verify, appcast signature check, stapler validate when notarized).

## Sparkle private key for CI

Export your existing Sparkle private key once on a trusted machine:

```bash
./scripts/release.sh
"build/release/SparkleToolsDerivedData/Build/Products/Release/generate_keys" \
  -x ~/sparkle-private-key.txt \
  --account "KarlApp.Report-Template"
```

Store the base64 value of that file in CI secret `SPARKLE_PRIVATE_KEY_BASE64`.
In production mode, key auto-generation is blocked to prevent accidental key rotation.

## CI production flow (GitHub Actions)

`.github/workflows/release.yml` enforces strict production mode on `v*` tag pushes.
Set these repository secrets:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APP_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`
- `SPARKLE_PRIVATE_KEY_BASE64`

You can set all required secrets with one command after exporting the values:

```bash
./scripts/configure_release_secrets.sh
```

## CI beta flow (GitHub Actions)

`.github/workflows/release-beta.yml` publishes unsigned prereleases for `beta-v*` tags.

Required secret:

- `SPARKLE_PRIVATE_KEY_BASE64`

## Key environment variables

- `RELEASE_CHANNEL`: `beta` or `production` (default: `beta`).
- `PRODUCTION_RELEASE`: `1` enables strict production gates.
- `DEVELOPER_ID_APP_IDENTITY`: enables Developer ID signing mode.
- `NOTARY_KEYCHAIN_PROFILE`: enables notarization when present (`NOTARIZE_ENABLED=auto`).
- `NOTARY_TEAM_ID`: optional explicit team ID for notary submission.
- `NOTARIZE_ENABLED`: `auto` (default), `1`, or `0`.  
  With `auto`, when `DEVELOPER_ID_APP_IDENTITY` is set, notarization is expected and the script fails if `NOTARY_KEYCHAIN_PROFILE` is missing.
- `SPARKLE_ALLOW_KEY_GENERATION`: default `1` for local mode, forced to `0` in production mode.
- `SPARKLE_PRIVATE_KEY_FILE` or `SPARKLE_PRIVATE_KEY_BASE64`: imports an existing Sparkle private key if keychain key is missing.
- `VERIFY_RELEASE_ARTIFACTS`: default `1`; runs release verification checks before success.
- `UPDATES_ENABLED_PLIST_KEY`: app plist key used to control Sparkle UI availability (`PPUpdatesEnabled` by default).

## How users install

- DMG route (recommended): open the DMG, drag `Report Template.app` into `Applications`.
- Terminal route (optional): run `install.sh` to download the latest stable DMG and install to `Applications`.
- Beta channel install: run `install.sh --beta` or install a `beta-v*` tag directly.

## Immediate containment for blocked installs

1. Delete `/Applications/Report Template.app`.
2. Install the latest `beta-v*` DMG from Releases.
3. Launch once with `Control` + click -> `Open`.
