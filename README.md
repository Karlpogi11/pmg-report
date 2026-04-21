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

Install latest release (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- --yes
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Karlpogi11/pmg-report/main/install.sh | bash -s -- v1.1
```

## Update app

Install the newer version the same way as above.
No uninstall is needed.

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
