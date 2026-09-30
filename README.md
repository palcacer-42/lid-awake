# Lid Awake

Keep a MacBook running with the **lid closed** — no external display, no HDMI
"dummy plug" required.

Normally macOS suspends a laptop when you shut the lid unless a real display is
attached (clamshell mode). Lid Awake flips the underlying power-management flag
so the machine keeps running with the lid shut, and gives you a simple on/off
button to control it.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## How it works

It toggles a long-standing (but undocumented) `pmset` setting:

```sh
sudo pmset -a disablesleep 1   # keep running with lid closed
sudo pmset -a disablesleep 0   # normal sleep on lid close
```

`pmset -g` reports the current state under the key `SleepDisabled` (note: the
key you *write* is `disablesleep`, but the key you *read* is `SleepDisabled`).

Lid Awake ships two front-ends for the same flag:

- **Lid Awake.app** — a small Swift/AppKit app: a window with a big toggle
  button, a Dock icon, and a menu-bar item.
- **`lid-toggle`** — a shell CLI for scripting (`lid-toggle on|off|status|toggle`).

## Requirements

- macOS 13 (Ventura) or newer — Apple Silicon or Intel.
- Xcode Command Line Tools (for `swiftc`): `xcode-select --install`

## Install

```sh
git clone https://github.com/palcacer-42/lid-awake.git
cd lid-awake
./install.sh
```

`install.sh` will:

1. Install the CLI to `~/.local/bin/lid-toggle`.
2. Add a passwordless `sudoers` rule so toggling never asks for a password
   (it will ask for your password **once**, to write the rule).
3. Build and install `~/Applications/Lid Awake.app`.

Then open **Lid Awake** from `~/Applications` (or Spotlight) and click the
button. The menu-bar icon shows the state at a glance: 👁 Awake / 🌙 Sleep.

### Manual / build only

```sh
./build.sh              # build ./dist/Lid Awake.app
./build.sh --install    # build and copy to ~/Applications
```

## Usage

| Action | How |
| --- | --- |
| Toggle | App window button, or menu-bar icon (left-click), or `lid-toggle` |
| Show window | Click the menu-bar icon |
| Menu | Right-click the menu-bar icon |
| Launch at login | Checkbox in the app window |
| From a script | `lid-toggle on` / `lid-toggle off` / `lid-toggle status` |

## Caveats

- **Heat & battery.** With the lid shut the internal display is off, but the
  SoC keeps running. That means more heat and faster battery drain, and a higher
  risk of thermal throttling if the Mac is in a bag. Turn it **off** when you
  don't need it.
- The `disablesleep` flag is **undocumented**. It has worked for years, but it
  isn't part of Apple's supported API surface.
- The setting **persists across reboots** until you toggle it off.
- The app is built locally and ad-hoc signed. If macOS blocks it, right-click
  the app → **Open**, or run `xattr -dr com.apple.quarantine "Lid Awake.app"`.

## Uninstall

```sh
./uninstall.sh
```

This restores normal sleep-on-lid-close and removes the app, CLI, login item,
and sudoers rule.

## Disclaimer

Use at your own risk. Keeping a laptop awake with the lid closed generates heat;
make sure the machine has airflow.

## License

[MIT](LICENSE)
