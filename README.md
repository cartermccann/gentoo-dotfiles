# gentoo-dotfiles

Gentoo + **MangoWM** desktop for **atlas** (Surface Laptop Studio).
Cobalt-on-near-black glass · switchable themes · fast-in/soft-out animations · SUPER-centric keys.

Authored to be cloned onto a freshly-installed Gentoo base and run with one script.

---

## What you get

| Layer | Pieces |
|-------|--------|
| **Compositor** | MangoWM (dwl + scenefx: blur/shadow/rounding + niri-style scroller) |
| **Desktop** | waybar · rofi · swaync · swaybg · swaylock · swayidle · wlsunset · grim/slurp · cliphist · ly login |
| **Terminals** | ghostty (default) · alacritty |
| **Audio** | PipeWire + WirePlumber + pavucontrol |
| **Bluetooth** | bluez + blueman |
| **Langs** | rust · go · zig · node · (bun/deno/uv via installers) · python |
| **CLI** | ripgrep, fd, eza, bat, zoxide, yazi, lazygit, just, atuin, … |
| **AI CLIs** | claude-code · codex · opencode · herdr |
| **Flatpak apps** | Zen · Spotify · Blanket  (Beeper + Helium: AppImage only) |
| **Shell** | fish + starship (themed cobalt prompt) + atuin + zoxide |
| **Editor** | neovim + LazyVim (`config/nvim`) with the theme-aware `atlas` colourscheme |
| **Dictation** | Parakeet TDT 0.6B via sherpa-onnx -> wtype  (`Super+Alt+L`) |

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
4. **dotfiles** – symlink `config/*` into `~/.config` (nvim included), set fish as shell
5. **theme** – install the `atlas-theme` switcher and apply the default (cobalt)

Then install the login manager and (optionally) the bootloader — both separate,
deliberate steps:

```bash
doas bash bin/setup-ly       # login manager (see below for the Manifest workaround)
doas bash bin/setup-limine   # bootloader, installed ALONGSIDE grub
```

### Bootloader (Limine)

`bin/setup-limine` installs Limine **next to GRUB, never over it** — GRUB's EFI
binary, its NVRAM entry and the kernels in `/boot` on btrfs are all left alone. The
first run arms `efibootmgr --bootnext`, a **one-shot** boot: if Limine fails, the next
reboot returns to GRUB by itself with nothing to undo. Promote it only once you've
seen it work.

```bash
doas bash bin/setup-limine              # install + arm the one-shot test
doas bash bin/setup-limine --default    # make it the default, after it boots clean
doas bash bin/setup-limine --revert     # remove it; GRUB untouched
PRUNE_DRY_RUN=1 doas bash bin/setup-limine   # show which dead NVRAM entries would go
```

Limine reads **FAT and ISO9660 only** (deliberate upstream policy), and this machine
keeps `/boot` on btrfs — so `system/kernel/postinst.d/95-limine.install` mirrors the
kernels onto the ESP and regenerates `limine.conf` on every kernel install. Gentoo's
`installkernel` has hooks for grub, systemd-boot, refind, efistub and uki but none for
limine; that file is the missing one. Colours come from the active atlas theme, so the
boot menu matches ly, waybar and neovim.

Then **reboot**. **ly** greets you → pick **Mango** → log in.

---

## Keybinds (Super = Windows key)

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `Super+Return` | ghostty | `Super+Space` | app launcher (rofi) |
| `Super+E` | file manager (thunar) | `Super+W` | Zen browser |
| `Super+Q` / `Super+W` | close window | `Super+Shift+E` | exit compositor |
| `Super+F` | maximize | `Super+Shift+F` | true fullscreen |
| `Super+hjkl` / arrows | focus | `Super+Shift+hjkl` | move window |
| `Super+T` | float toggle | `Super+Ctrl+S` | **scroller** (niri-style) |
| `Super+1..9` | switch tag | `Super+Shift+1..9` | send window to tag |
| `Super+B` | toggle bar | `Super+Shift+S` | region screenshot |
| `Super+V` | clipboard history | `Super+Tab` | next workspace |
| `Super+Escape` | lock | `Super+Shift+R` | reload config |
| `Super+Alt+T` | theme picker | `Super+Shift+T` | toggle light/dark |
| `Super+Alt+L` | dictation | `Super+Ctrl+N` | night light |

Full map: `config/mango/bind.conf` — ported from kronos Hyprland, so muscle
memory carries over. Binds with no mango equivalent are listed at the bottom of
that file rather than silently dropped.

---

## Known gaps / things to verify

### The base-profile trap (read this first)

This system uses the **base 23.0 profile**, not `desktop`, so the binhost's USE
flags keep matching. The cost is that the profile enables **nothing**, and seven
separate packages shipped broken because of it. All seven fixes live in
`system/portage/package.use/atlas`; they are listed here because the failures are
silent and the symptom never points at the cause:

| package | default | symptom |
|---------|---------|---------|
| `x11-terms/ghostty` | `-wayland` | `REQUIRED_USE any-of ( X wayland )`, won't build |
| `dev-cpp/gtkmm`, `xfce-base/*` | `-wayland -X` | same; blocks **waybar** and **thunar** |
| `sys-auth/seatd` | all backends off | **mango would not start at all** — libseat "No backend was able to open a seat" |
| `gui-apps/waybar` | `-tray -pulseaudio -network -backlight -mpris` | modules parse fine and silently never render |
| `gui-apps/swaybg` | `-gdk-pixbuf` | PNG-only; blank wallpaper, error only on its stderr |
| `x11-libs/gdk-pixbuf` | `-jpeg` | **any GTK app** fails to decode a jpg |
| `media-fonts/nerdfonts` | symbols-only | every config asking for JetBrainsMono silently falls back |

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
- **Login manager is `ly`.** Install it with `doas bash bin/setup-ly` — it is
  deliberately NOT in the `packages` phase, because it needs a workaround and
  that should be an explicit, auditable step rather than something the installer
  does quietly.

  **Why ly needs a workaround:** GURU's Manifest no longer matches what Codeberg
  serves. Codeberg builds archive tarballs on demand and the gzip output is not
  byte-reproducible, so verification fails (`Filesize does not match recorded
  size — Got: 146988  Expected: 147223`). The `404` portage prints first is only
  `distfiles.gentoo.org`, which does not mirror GURU distfiles; upstream itself
  returns 200. All three GURU versions (1.3.2/1.4.0/1.4.1) fail identically.
  `bin/setup-ly` re-digests the ebuild — which means the integrity check no
  longer proves anything about the contents — and `emerge --sync guru` wipes it,
  so it must be redone after each sync. Worth filing upstream at GURU.

  ly does real 24-bit colour (`0xSSRRGGBB` with `full_color = true`), so it
  renders the actual cobalt `#3b6bff` on the box border, over a cobalt→navy→black
  `colormix` shader. Config: `system/ly/config.ini`.

  **tty2 conflict:** ly's init script hardcodes `TTY="tty2"` and runs
  `agetty -nl /usr/bin/ly tty2`, while Gentoo's `/etc/inittab` line `c2` also
  respawns a plain agetty there. Both fight for the terminal and the greeter
  flickers or respawn-loops. `bin/setup-ly` comments out `c2` only.

  **Recovery:** `c1` and `c3`–`c6` are left alone, so if ly fails to come up
  `Ctrl+Alt+F1` still gives a console, and `exec mango` starts the desktop
  directly.
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
ghostty, alacritty, rofi, swaync, swaylock, starship, **neovim** and the Mango
window borders together.

Neovim is themed the same way starship is: a tracked colourscheme
(`config/nvim/colors/atlas.lua`) plus a generated palette. Every syntax role is
derived from the theme's own 16 colours using VS Code Dark+ semantics, so a new
theme needs no editor work at all -- see `design/nvim-mockup.html` for the mapping
rendered across all seven. A running nvim watches the generated palette and
re-sources itself, so it recolours mid-session like the bar does.

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
│   ├── ly/config.ini     # login manager (cobalt, 24-bit)
│   └── services.conf     # declarative <service> <runlevel>
├── bin/setup-ly          # installs ly (GURU Manifest workaround, documented)
├── themes/<name>/colors.sh
├── bin/atlas-theme
├── config/nvim/          # LazyVim + the theme-aware `atlas` colourscheme
│   ├── colors/atlas.lua  #   tracked: roles -> ~300 highlight groups
│   └── lua/atlas/        #   roles.lua (derivation) · fallback.lua · lualine.lua
├── dictation/            # Parakeet setup + transcribe + toggle
└── design/               # shell + nvim mockups (design contracts)
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
