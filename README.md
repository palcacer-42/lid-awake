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

### Homebrew

```sh
brew install --cask palcacer-42/tap/lid-awake
```

Homebrew will ask you to trust the third-party tap the first time. The app is
not notarized, so on first launch use **right-click → Open** (or
`xattr -dr com.apple.quarantine "/Applications/Lid Awake.app"`). You still need
the one-time sudoers rule below (Homebrew prints it as a caveat).

### From source

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
button. The app also lives in the menu bar, Caffeine-style: a filled cup icon
means lid-awake is active, a hollow cup means it is inactive. Click the icon
for a menu with the toggle, Launch at Login, and About/Quit.

### Manual / build only

```sh
./build.sh              # build ./dist/Lid Awake.app (generates the icon too)
./build.sh --install    # build and copy to ~/Applications
./make-icon.sh          # regenerate AppIcon.icns on its own
```

## Usage

| Action | How |
| --- | --- |
| Toggle | Menu-bar icon → Enable/Disable, app window button, or `lid-toggle` |
| Menu | Click the menu-bar cup icon (filled = active, hollow = inactive) |
| Launch at login | "Launch at Login" in the menu-bar menu, or the app window checkbox |
| Show window | Menu-bar icon → Show Window |
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
