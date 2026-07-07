# AutoInputSwitcher

AutoInputSwitcher is a small native macOS app that switches the keyboard input source based on the foreground application.

It is intentionally simple:

- Lists installed macOS apps.
- Lets each app stay on `-` for no automatic switch.
- Saves per-app input source rules locally.
- Runs in the background after closing the window.
- Does not show a Dock icon or menu bar item.
- Can launch at login.
- Counts successful automatic switches.

## Requirements

- macOS 14 or later
- Swift 6 toolchain
- Command Line Tools or Xcode

## Run Locally

```bash
./Scripts/test.sh
./Scripts/build-app.sh
open .build/AutoInputSwitcher.app
```

## Package a Release Build

```bash
./Scripts/package-release.sh
```

The release archive is written to:

```text
.build/dist/AutoInputSwitcher-macOS.zip
```

## Usage

Each installed app appears in the table. Select `-` to leave that app untouched, or select a keyboard input source to switch automatically when that app becomes active.

The app uses `LSUIElement`, so it does not show a Dock icon or menu bar item. Closing the window keeps the app running. Reopen the app from Finder, Spotlight, or Launchpad to show the window again. Use the `退出` button to quit the background process.

## GitHub Actions

`.github/workflows/release.yml` runs on pushes to `main` and manual dispatches.

- `checks`: runs `./Scripts/test.sh` and is non-blocking.
- `build`: packages the macOS app and uploads the zip artifact.
- `release`: creates a GitHub Release with `AutoInputSwitcher-macOS.zip`.
