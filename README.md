# PMG Report (macOS)

Simple report app for macOS.

## Download

- [Releases Page](https://github.com/Karlpogi11/pmg-report/releases)

## Install (Recommended: DMG)

1. Download `Report-Template-<version>.dmg` from your target channel:
   - Production (`v*` tags): notarized release, no Gatekeeper warning expected.
   - Beta (`beta-v*` tags): unsigned prerelease, one-time manual Open is required.
2. Open the DMG.
3. Drag `Report Template.app` to `Applications`.

## Install (Terminal Option)

Install latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash
```

Install latest beta release:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- --beta
```

The installer checks your installed app version first and skips download when you're already on the latest stable release.

Install latest release (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- --yes
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- v1.1
```

Install a specific beta tag:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- beta-v1.1.6-beta.1
```

## Update app

- Production builds: use `Check Update` inside the app toolbar (Sparkle).
- Beta builds: in-app update checks are disabled by design; install newer beta DMGs manually.
- Manual install from Releases still works; no uninstall is needed.

## If macOS blocks first launch

1. `Control` + click `Report Template.app`
2. Click `Open`
3. Confirm `Open`

## Quick Unblock (Existing Blocked Install)

1. Delete `/Applications/Report Template.app`.
2. Install the latest beta DMG (`beta-v*`) from Releases.
3. Launch once using `Control` + click -> `Open`.

## For Maintainers

Build release files:

```bash
./scripts/release.sh
```

Output files are in `dist/`:

- `Report-Template-<version>.dmg`
- `appcast.xml` (signed Sparkle feed)

Build unsigned beta artifacts (updates disabled in-app):

```bash
RELEASE_CHANNEL=beta \
SPARKLE_ALLOW_KEY_GENERATION=0 \
SPARKLE_PRIVATE_KEY_BASE64="<base64-private-key>" \
./scripts/release.sh
```

For production-ready releases (Developer ID signing + notarization), run:

```bash
RELEASE_CHANNEL=production \
PRODUCTION_RELEASE=1 \
DEVELOPER_ID_APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="karlapp-notary" \
NOTARY_TEAM_ID="TEAMID" \
SPARKLE_ALLOW_KEY_GENERATION=0 \
./scripts/release.sh
```

See maintainer details in [RELEASE.md](./RELEASE.md).
