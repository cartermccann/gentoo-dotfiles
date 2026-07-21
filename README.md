# gentoo-dotfiles

Gentoo + **MangoWM** desktop for **atlas** (Surface Laptop Studio).
Cobalt-on-near-black glass · switchable themes · fast-in/soft-out animations · SUPER-centric keys.

Authored to be cloned onto a freshly-installed Gentoo base and run with one script.

---

## What you get

| Layer | Pieces |
|-------|--------|
| **Compositor** | MangoWM (dwl + scenefx: blur/shadow/rounding + niri-style scroller) |
| **Desktop** | waybar · rofi · swaync · swaybg · swaylock · swayidle · wlsunset · grim/slurp · greetd+tuigreet login |
| **Terminals** | ghostty (default) · alacritty · foot |
| **Audio** | PipeWire + WirePlumber + pavucontrol (+ EasyEffects) |
| **Bluetooth** | bluez + blueman |
| **Langs** | rust · go · zig · node · (bun/deno/uv via installers) · python |
| **CLI** | ripgrep, fd, eza, bat, zoxide, yazi, lazygit, just, atuin, … |
| **AI CLIs** | claude-code · codex · opencode · herdr |
| **Flatpak apps** | Zen · Spotify · Blanket  (Beeper + Helium: AppImage only) |
| **Shell** | fish + starship + atuin + zoxide |
| **Editor** | neovim + your LazyVim config, pulled from `cartermccann/dotfiles` |
| **Dictation** | Parakeet TDT 0.6B via sherpa-onnx -> wtype  (`Super+Ctrl+D`) |

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
2. **flatpaks** – Zen, Spotify, Blanket (`--user` scope)
3. **ai** – claude-code, codex, opencode, herdr + bun/deno/uv
4. **dotfiles** – symlink `config/*` into `~/.config`, clone nvim, set fish as shell
5. **theme** – install the `atlas-theme` switcher and apply the default (cobalt)

Then **reboot**. **tuigreet** greets you on vt7 → pick **Mango** → log in.

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

Everything below was found on the real atlas install and is already handled by the
installer; they are documented because they will bite again on a fresh machine.

- **CLI tool atoms** — the `packages` phase installs the tool list resiliently
  (tries each, reports misses). If it lists "unresolved tools", fix the atom with
  `emerge -s <name>` and add it.
- **herdr** — needs **Zig 0.15.2**, not the newest zig. Its vendored `libghostty-vt`
  `@compileError`s on 0.16 (`Dir.readFileAlloc` changed arity), so the ai phase puts
  `/opt/zig-bin-0.15.2` first on PATH for that one build. If it still fails, drop a
  release binary into `~/.local/bin`.
- **Helium browser** — not on Flathub (verified: `flatpak search helium` returns only a
  GTK theme). Grab the AppImage from `github.com/imputnet/helium-chromium/releases`.
- **Beeper** — no Flathub app-id exists at all. Download the Linux AppImage from
  `beeper.com/download`.
- **Monitor refresh** — `config/mango/monitor.conf` starts eDP-1 at **60 Hz + scale 1.5**
  for a safe first boot. Run `wlr-randr` and bump to 120 Hz once you confirm it's stable.
- **Login manager is greetd + tuigreet, not ly.** `x11-misc/ly` (GURU) fails to
  fetch: Codeberg generates its archive tarballs on the fly and the output is not
  byte-reproducible, so the recorded Manifest no longer matches what the server
  serves (expects 147223 bytes, gets 146988 — `VERIFY FAILED! Filesize does not
  match recorded size`). The `404` you see first is only portage trying
  `distfiles.gentoo.org`, which does not mirror GURU distfiles; it is not the
  real cause. Fixable locally with
  `doas ebuild /var/db/repos/guru/x11-misc/ly/ly-1.4.1.ebuild manifest`, but that
  re-digests against whatever Codeberg serves (so it trusts an unverified
  download) and is wiped by the next `emerge --sync guru`. All three GURU
  versions (1.3.2, 1.4.0, 1.4.1) are affected the same way. greetd is configured on
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
├── install.sh            # orchestrator  (--dry-run, --check, --list)
├── lib/common.sh         # logging/TUI, doas, symlink + deploy helpers
├── phases/               # 10-packages · 20-flatpaks · 30-ai-tools · 40-dotfiles · 50-theme
├── config/               # -> symlinked into ~/.config  (user-owned)
├── system/               # -> copied into /etc          (root-owned, see below)
│   ├── portage/package.{use,accept_keywords}/atlas
│   ├── greetd/config.toml · init.d/greetd
│   └── services.conf     # declarative <service> <runlevel>
├── themes/<name>/colors.sh
├── bin/atlas-theme
├── dictation/            # Parakeet setup + transcribe + toggle
└── design/               # shell mockup (design contract)
```

### Why `system/` is copied and `config/` is symlinked

`~/.config` symlinks straight into the repo, so editing a config here changes the
live system immediately. `/etc` does **not**: those files are copied. `/etc/portage`
decides what root emerges and `/etc/init.d` runs as root at boot, so pointing either
at a user-writable git checkout would mean anyone who can write the checkout controls
root. The tradeoff is that `/etc` can drift, so:

```bash
./install.sh --check      # diff repo vs live: /etc files, ~/.config symlinks,
                          # enabled services, and unmerged ._cfg files
```

`._cfg` files are worth checking: portage's autounmask leftovers can be **stale**, and
merging one blindly can revert newer config. Diff before `dispatch-conf`.
