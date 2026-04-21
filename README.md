# PMG Report (macOS)

Simple report app for macOS.

## Download

- [Releases Page](https://github.com/Karlpogi11/pmg-report/releases)

## Install (Recommended: DMG)

1. Download `Report-Template-<version>.dmg`.
2. Open the DMG.
3. Drag `Report Template.app` to `Applications`.

## Install (Terminal Option)

Install latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash
```

The installer checks your installed app version first and skips download when you're already on latest.

Install latest release (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- --yes
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- v1.1
```

## Update app

Use `Check Update` inside the app toolbar (Sparkle).
Manual install from Releases still works; no uninstall is needed.

## If macOS blocks first launch

1. `Control` + click `Report Template.app`
2. Click `Open`
3. Confirm `Open`

## For Maintainers

Build release files:

```bash
./scripts/release.sh
```

Output files are in `dist/`:

- `Report-Template-<version>.dmg`
- `appcast.xml` (signed Sparkle feed)

For production-ready releases (Developer ID signing + notarization), run:

```bash
PRODUCTION_RELEASE=1 \
DEVELOPER_ID_APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="karlapp-notary" \
NOTARY_TEAM_ID="TEAMID" \
SPARKLE_ALLOW_KEY_GENERATION=0 \
./scripts/release.sh
```

See maintainer details in [RELEASE.md](./RELEASE.md).
