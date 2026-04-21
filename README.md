# PMG Report (macOS)

Simple report app for macOS.

## Download

- [Releases Page](https://github.com/Karlpogi11/pmg-report/releases)

## Install (User Friendly)

### Option 1: One-click installer (easiest)

1. Open [Releases Page](https://github.com/Karlpogi11/pmg-report/releases).
2. Download `Report-Template-<version>-installer.command`.
3. Double-click the file.
4. Follow the prompts.

### Option 2: DMG install

1. Download `Report-Template-<version>.dmg`.
2. Open the DMG.
3. Drag `Report Template.app` to `Applications`.

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
- `Report-Template-<version>-installer.command`
- `Report-Template-<version>-installer.sh`
