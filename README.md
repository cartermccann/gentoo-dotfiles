# gentoo-dotfiles

Gentoo + **MangoWM** desktop for **atlas** (Surface Laptop Studio).
Cobalt-on-near-black glass · switchable themes · fast-in/soft-out animations · SUPER-centric keys.

Authored to be cloned onto a freshly-installed Gentoo base and run with one script.

---

## What you get

| Layer | Pieces |
|-------|--------|
| **Compositor** | MangoWM (dwl + scenefx: blur/shadow/rounding + niri-style scroller) |
| **Desktop** | waybar · rofi · mako · swaybg · swaylock · wlsunset · grim/slurp · ly login |
| **Terminals** | ghostty (default) · alacritty · foot |
| **Audio** | PipeWire + WirePlumber + pavucontrol (+ EasyEffects) |
| **Bluetooth** | bluez + blueman |
| **Langs** | rust · go · zig · node · (bun/deno/uv via installers) · python |
| **CLI** | ripgrep, fd, eza, bat, zoxide, yazi, lazygit, just, atuin, … |
| **AI CLIs** | claude-code · codex · opencode · herdr |
| **Flatpak apps** | Zen · Spotify · Beeper · Blanket · (Helium: AppImage) |
| **Shell** | fish + starship + atuin + zoxide |
| **Editor** | your LazyVim config, pulled from `cartermccann/dotfiles` |

---

## Prerequisites (already done during the Gentoo install)

- Booted Gentoo base, GRUB, working **Wi-Fi** (`wlp242s0`)
- `elogind` + `dbus` + `seatd` present
- `doas` configured (`permit persist :wheel`), user in `wheel`

## Install

```bash
git clone https://github.com/cartermccann/gentoo-dotfiles ~/gentoo-dotfiles
cd ~/gentoo-dotfiles
./install.sh              # all phases, in order
# or preview first:
./install.sh --dry-run
# or a single layer:
./install.sh dotfiles
```

Phases (`./install.sh --list`):

1. **packages** – emerge the desktop stack, CLI tools, langs, audio, bluetooth; enable GURU; write keyword/USE overrides; enable services (needs `doas`)
2. **flatpaks** – Zen, Spotify, Beeper, Blanket
3. **ai** – claude-code, codex, opencode, herdr + bun/deno/uv
4. **dotfiles** – symlink `config/*` into `~/.config`, clone nvim, set fish as shell
5. **theme** – install the `atlas-theme` switcher and apply the default (cobalt)

Then **reboot**. `ly` greets you → pick **Mango** → log in.

---

## Keybinds (Super = Windows key)

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `Super+Return` | ghostty | `Super+D` | app launcher (rofi) |
| `Super+E` | file manager (thunar) | `Super+W` | Zen browser |
| `Super+Q` | close window | `Super+Shift+Q` | exit compositor |
| `Super+F` | fullscreen | `Super+Shift+Space` | float toggle |
| `Super+hjkl` / arrows | focus | `Super+Shift+hjkl` | move window |
| `Super+T` | tile layout | `Super+S` | **scroller** (niri-style) |
| `Super+1..9` | switch tag | `Super+Shift+1..9` | send window to tag |
| `Super+B` | toggle bar | `Super+Shift+S` | region screenshot |
| `Super+Escape` | lock | `Super+Shift+R` | reload config |
| `Super+Ctrl+T` | theme picker | `Super+Shift+T` | toggle light/dark |

Full map: `config/mango/bind.conf`.

---

## Known gaps / things to verify

These are flagged because the repo was authored on another machine and can't be
tested on atlas until you run it:

- **CLI tool atoms** — the `packages` phase installs the tool list resiliently
  (tries each, reports misses). If it lists "unresolved tools", fix the atom with
  `emerge -s <name>` and add it.
- **ghostty** — expected in GURU (`gui-apps/ghostty`). If the atom differs or it's
  absent, build from source with zig (already installed): the Ghostty docs cover it.
- **herdr** — installed via `cargo install --git … --tag v0.7.1`. If that fails,
  drop a release binary into `~/.local/bin`.
- **Helium browser** — not on Flathub (verified: `flatpak search helium` returns only a
  GTK theme). Grab the AppImage from `github.com/imputnet/helium-chromium/releases`.
- **Beeper** — no Flathub app-id exists at all. Download the Linux AppImage from
  `beeper.com/download`.
- **Monitor refresh** — `config/mango/monitor.conf` starts eDP-1 at **60 Hz + scale 1.5**
  for a safe first boot. Run `wlr-randr` and bump to 120 Hz once you confirm it's stable.
- **Login manager is greetd + tuigreet, not ly.** `x11-misc/ly`'s only ebuild (1.4.1)
  404s on its upstream tarball, so it cannot be installed. greetd is configured on
  **vt7** — `agetty` keeps tty1–6, so a broken greeter never locks you out
  (Ctrl+Alt+F7 = login screen, Ctrl+Alt+F1 = plain console).
  Gentoo's greetd ships *only* a systemd unit, so this repo provides the OpenRC
  init script at `system/init.d/greetd`; without it `rc-update add greetd` silently
  does nothing.
- **fish** — a starter `config.fish` is included (starship/zoxide/atuin + aliases).
  Port the rest of your kronos fish functions when you want them.

## Theme system

`atlas-theme` is an Omarchy-style unified switcher: one palette
(`themes/<name>/colors.sh`) is rendered into every app's colors and reloaded live.

```bash
atlas-theme            # rofi picker            (Super+Ctrl+T)
atlas-theme toggle     # cobalt <-> cobalt-light (Super+Shift+T)
atlas-theme set nord   # apply by name
atlas-theme list       # cobalt · cobalt-light · tokyo-night · nord · gruvbox · everforest · kanagawa
```

Design idiom: cobalt accent on near-black glass, with a ChatGPT-clean light mode as
the counterweight (see `design/shell-mockup.html`). Switching retints waybar,
ghostty, alacritty, foot, rofi, mako and the Mango window borders together.

**Add a theme** — drop a `themes/<name>/colors.sh` defining the palette
(`GROUND/BASE/SURFACE/TEXT/ACCENT` + the 16 terminal colors `T0..T15`); it appears
in the picker automatically. Seven ship today: Cobalt (+ light), Tokyo Night, Nord,
Gruvbox, Everforest, Kanagawa.

> The `theme.*` files that appear inside `config/*/` are generated by the switcher
> and git-ignored — the source of truth is `themes/*/colors.sh`.

---

## Layout

```
gentoo-dotfiles/
├── install.sh            # orchestrator
├── lib/common.sh         # logging, doas, symlink helpers
├── phases/               # 10-packages · 20-flatpaks · 30-ai-tools · 40-dotfiles
└── config/               # mango, ghostty, alacritty, foot, waybar, rofi, mako, fish
```
