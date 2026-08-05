#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  atlas-dotfiles installer
#  Surface Laptop Studio · Gentoo · MangoWM
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

export DRY_RUN=0

# phase short-name → script
declare -A PHASE_FILES=(
    [packages]="10-packages.sh"
    [flatpaks]="20-flatpaks.sh"
    [apps]="25-apps.sh"
    [vendored]="27-vendored.sh"
    [ai]="30-ai-tools.sh"
    [devtools]="32-devtools.sh"
    [services]="35-services.sh"
    [dotfiles]="40-dotfiles.sh"
    [fonts]="45-fonts.sh"
    [theme]="50-theme.sh"
)
ORDER=(packages flatpaks apps vendored ai devtools services dotfiles fonts theme)

usage() {
    cat <<EOF
${C_BOLD}atlas-dotfiles installer${C_RESET}

Usage: ./install.sh [options] [phase ...]

Phases (run in this order if none given):
  packages   emerge desktop stack, CLI tools, langs, audio, bluetooth (needs doas)
  flatpaks   Zen, Spotify, Blanket via Flatpak (--user scope)
  apps       Obsidian, 1Password, Slack, OBS from portage (optional, needs doas)
  vendored   prebuilt apps nobody packages (Codex desktop) -> ~/apps
  ai         claude-code, codex, opencode, herdr + bun/deno/uv runtimes
  devtools   deploy/cloud/API CLIs from portage, npm, uv and upstream installers
  services   s6 user supervision tree for session daemons
  dotfiles   seed configs into ~/.config (incl. nvim) — copies, never overwrites
  theme      seed atlas-theme + themes and apply the default (cobalt)

Options:
  --dry-run   print what would happen, change nothing
  --check     machine health: boot chain, clock mitigation, pending ._cfg (~4s)
  --check-rebuild
              resolve @world from scratch: could a CLEAN CHECKOUT build this
              machine? changes nothing (~25s)
  --harvest   pull live configs back into the repo to refresh the seed,
              then review with git diff
  --list      list phases and exit
  -h, --help  this help

Examples:
  ./install.sh                 # everything, in order
  ./install.sh dotfiles        # just deploy configs
  ./install.sh --dry-run       # preview the whole run
EOF
}

# ── The system files this repo seeds ───────────────────────────
# One list, two readers: the bootstrap deploy on a fresh machine, and
# --harvest, which pulls the live copies back into the repo so the seed
# stays worth planting. This repo does not OWN these files — the live
# /etc does; the map is a manifest, not a claim.
system_file_map() {
    cat <<'MAP'
system/portage/make.conf /etc/portage/make.conf
system/portage/package.accept_keywords/atlas /etc/portage/package.accept_keywords/atlas
system/portage/package.use/atlas /etc/portage/package.use/atlas
system/portage/package.license/atlas /etc/portage/package.license/atlas
system/portage/package.mask/atlas /etc/portage/package.mask/atlas
system/portage/repos.conf/eselect-repo.conf /etc/portage/repos.conf/eselect-repo.conf
system/portage/binrepos.conf/gentoo.conf /etc/portage/binrepos.conf/gentoo.conf
system/portage/bashrc /etc/portage/bashrc
system/portage/sets/atlas-bootstrap /etc/portage/sets/atlas-bootstrap
system/portage/sets/atlas-core /etc/portage/sets/atlas-core
system/portage/sets/atlas-tools /etc/portage/sets/atlas-tools
system/portage/sets/atlas-apps /etc/portage/sets/atlas-apps
system/portage/sets/atlas-devtools /etc/portage/sets/atlas-devtools
system/ly/config.ini /etc/ly/config.ini
system/kernel/cmdline /etc/kernel/cmdline
system/kernel/postinst.d/95-limine.install /etc/kernel/postinst.d/95-limine.install
system/dracut.conf.d/atlas.conf /etc/dracut.conf.d/atlas.conf
system/btrbk/btrbk.conf /etc/btrbk/btrbk.conf
system/conf.d/consolefont /etc/conf.d/consolefont
system/wayland-sessions/mango.desktop /usr/share/wayland-sessions/mango.desktop
system/portage/env/no-session-desktop.conf /etc/portage/env/no-session-desktop.conf
system/portage/package.env/atlas /etc/portage/package.env/atlas
system/udev/99-worklouder.rules /etc/udev/rules.d/99-worklouder.rules
MAP
}

# ── --harvest: refresh the seed from the live machine ──────────
# The reverse of installing. The live system is the source of truth; this
# repo is a bootstrap snapshot of it. Run this when the snapshot has earned
# a refresh — after settling a config a fresh machine should start from —
# then review `git diff` and commit. Only paths the repo already seeds are
# pulled; a new app's config is added deliberately, never swept in.
run_harvest() {
    banner "atlas / harvest" "live system -> repo seed"

    step "system files (/etc and friends)"
    while read -r src dst; do
        [ -z "$src" ] && continue
        if [ ! -f "$dst" ]; then
            warn "absent live: $dst (repo copy left as-is)"
        elif [ ! -r "$dst" ]; then
            warn "unreadable: $dst (root-only — pull by hand with doas if it changed)"
        elif cmp -s "$dst" "$REPO_DIR/$src"; then
            :
        else
            cp -a "$dst" "$REPO_DIR/$src" && ok "pulled $dst"
        fi
    done < <(system_file_map)

    step "user configs (~/.config)"
    local name
    for dir in "$REPO_DIR"/config/*/; do
        name="$(basename "${dir%/}")"
        [ -d "$HOME/.config/$name" ] || { warn "absent live: ~/.config/$name"; continue; }
        rsync -a --delete "$HOME/.config/$name/" "$dir" && ok "pulled ~/.config/$name"
    done

    step "login shell files"
    cp -a "$HOME/.profile"      "$REPO_DIR/home/profile"
    cp -a "$HOME/.bash_profile" "$REPO_DIR/home/bash_profile"
    ok "pulled ~/.profile + ~/.bash_profile"

    step "scripts (bin/ + dictation/)"
    local b
    for b in atlas-theme atlas-svc atlas-wallpaper atlas-firmware-setup; do
        [ -f "$HOME/.local/bin/$b" ] && cp -a "$HOME/.local/bin/$b" "$REPO_DIR/bin/$b"
    done
    for b in toggle-dictation.sh setup-dictation.sh; do
        [ -f "$HOME/.local/bin/$b" ] && cp -a "$HOME/.local/bin/$b" "$REPO_DIR/dictation/$b"
    done
    ok "pulled atlas-* + dictation scripts"

    step "s6 service definitions (~/.config/s6)"
    # Definitions only — run and log/run. The supervise/ and event/ dirs are
    # s6 runtime state and never belong in the repo. New services ARE picked
    # up: a service you defined live is exactly what a fresh machine needs.
    local d
    for d in "$HOME/.config/s6"/*/; do
        [ -f "$d/run" ] || continue
        name="$(basename "${d%/}")"
        mkdir -p "$REPO_DIR/services/$name/log"
        cp -a "$d/run" "$REPO_DIR/services/$name/run"
        [ -f "$d/log/run" ] && cp -a "$d/log/run" "$REPO_DIR/services/$name/log/run"
        ok "pulled service $name"
    done

    step "themes"
    rsync -a --delete "${XDG_DATA_HOME:-$HOME/.local/share}/atlas-theme/themes/" \
        "$REPO_DIR/themes/" && ok "pulled themes"

    step "launcher stubs"
    local f
    for f in "$REPO_DIR"/share/applications/*.desktop; do
        b="$(basename "$f")"
        [ -f "$HOME/.local/share/applications/$b" ] && \
            cp -a "$HOME/.local/share/applications/$b" "$f"
    done
    ok "pulled tracked .desktop stubs"

    echo
    ok "harvest complete — review:  git -C $REPO_DIR diff"
}

# ── --check: machine health, not repo drift ────────────────────
# Scope, re-settled 2026-08-05 (second pass, same day as the convergence
# retreat): this repo is a ONE-TIME bootstrap. The live system is the source
# of truth for every config; nothing here polices what /etc or ~/.config
# contain. What remains are the checks whose failures brick or bewilder the
# machine and that nothing else watches: the boot chain (limine + ESP + /boot
# agreement), the swclock mitigation for the Surface's decoy RTC, and
# unmerged ._cfg files (which have carried STALE content here before —
# never blind-merge them). Everything else that used to live here —
# file-by-file /etc diffs, symlink policing, undeclared-portage scans,
# declared-vs-installed package audits — died with the ownership model.
run_check() {
    banner "atlas / health check" "boot chain · clock · pending config"
    local drift=0

    # ── /boot and the ESP ──────────────────────────────────────────
    # The blind spot this closes: every other check here reasons about packages,
    # /etc, services or s6, and NONE of them can see a boot artifact. That gap
    # is structural, not an oversight -- installkernel writes /boot in
    # pkg_postinst, so those files are in no package's CONTENTS and portage
    # cannot account for them. Checking "is this file owned?" is useless here:
    # EVERY /boot kernel comes back unowned, including the running one. Staleness
    # has to be derived from versions instead.
    #
    # It matters because the failures are silent and only surface at the next
    # boot, which may be weeks away. On 2026-08-05 alone: a depclean removed the
    # kernel package and left /boot and the ESP untouched; and eclean-kernel
    # cleaned /boot but not the ESP, leaving limine offering a kernel that no
    # longer existed upstream -- while every path in limine.conf still resolved,
    # because the ESP kept its own copy. That last one is why the mirror is
    # checked in BOTH directions rather than just resolving the menu's paths.
    # ESP/BOOTDIR/MODDIR/RUNNING are overridable for the same reason the
    # generator's are: a check whose failure branches have never been executed
    # is a check that has only ever been observed passing. Every failure branch
    # below was fired against a fake ESP/BOOTDIR tree before this was committed;
    # the cases are listed in the commit message.
    step "boot artifacts (/boot + ESP)"
    local ESPDIR="${ESP:-/efi}" BOOTD="${BOOTDIR:-/boot}" MODD="${MODDIR:-/lib/modules}"
    local KDIR="$ESPDIR/atlas" LCONF="$ESPDIR/limine.conf"
    if [ ! -d "$ESPDIR/EFI/Limine" ]; then
        info "ESP not mounted or limine not installed — skipping"
    elif [ ! -r "$LCONF" ]; then
        err "no $LCONF — the bootloader has no config"; drift=1
    else
        local missing="" noentry="" espextra="" mismatch=""
        local running="${RUNNING_KERNEL:-$(uname -r)}"

        # 1. Every path the menu names must exist ON THE ESP. Limine reads FAT
        #    only (see the hook's header), so /boot existing is not enough.
        while read -r p; do
            [ -f "$ESPDIR$p" ] || missing="$missing $p"
        done < <(grep -oE '(path|module_path): boot\(\):/[^ ]+' "$LCONF" | sed 's|.*boot():||')

        # 2. ...and every kernel in /boot must be offered. A kernel present but
        #    absent from the menu is one you cannot select when you need it.
        for k in "$BOOTD"/vmlinuz-*; do
            [ -e "$k" ] || continue
            grep -q "path: boot():/atlas/$(basename "$k")\$" "$LCONF" || noentry="$noentry $(basename "$k")"
        done

        # 3. Mirror, both ways. ESP->/boot catches the eclean-kernel case above;
        #    content comparison catches a copy that was interrupted or a /boot
        #    file rebuilt without the hook running.
        for f in "$KDIR"/*; do
            [ -f "$f" ] || continue
            local b; b=$(basename "$f")
            if [ ! -f "$BOOTD/$b" ]; then espextra="$espextra $b"
            elif ! cmp -s "$f" "$BOOTD/$b"; then mismatch="$mismatch $b"; fi
        done

        [ -n "$missing" ] && { err "limine.conf names files that do not exist on the ESP:"
            printf '      %s\n' $missing
            info "      the menu offers entries that will not boot"
            info "      fix: doas /etc/kernel/postinst.d/95-limine.install"; drift=1; }
        [ -n "$noentry" ] && { warn "in /boot but not in the menu:"
            printf '      %s\n' $noentry
            info "      fix: doas /etc/kernel/postinst.d/95-limine.install"; drift=1; }
        [ -n "$espextra" ] && { warn "on the ESP with no /boot counterpart:"
            printf '      %s\n' $espextra
            info "      the hook prunes these, but only when a kernel is INSTALLED"
            info "      fix: doas /etc/kernel/postinst.d/95-limine.install"; drift=1; }
        [ -n "$mismatch" ] && { err "ESP copy differs from /boot:"
            printf '      %s\n' $mismatch
            info "      you would boot something other than what /boot holds"
            info "      fix: doas /etc/kernel/postinst.d/95-limine.install"; drift=1; }
        [ -z "$missing$noentry$espextra$mismatch" ] &&
            ok "limine.conf and the ESP agree with /boot"

        # 4. The three copies must agree. Limine checks the EFI app path FIRST,
        #    then the ESP root, so a stale copy at one of them is what actually
        #    boots while the one you edited looks correct.
        local hashes; hashes=$(md5sum "$LCONF" "$ESPDIR"/EFI/*/limine.conf 2>/dev/null | awk '{print $1}' | sort -u | wc -l)
        if [ "$hashes" = "1" ]; then ok "all limine.conf copies identical"
        else err "limine.conf copies DISAGREE — the one Limine reads may not be the one you edited"; drift=1; fi

        # 5. A menu entry with no root= boots to a kernel panic, and the hook
        #    refuses to write one, so this catches hand-editing only.
        local nent nroot
        nent=$(grep -c '^/Gentoo' "$LCONF"); nroot=$(grep -c 'cmdline:.*root=' "$LCONF")
        if [ "$nent" = "$nroot" ]; then ok "every entry carries root= ($nent)"
        else err "$((nent - nroot)) of $nent entries have no root="; drift=1; fi

        # 6. You must be able to get back to what you are running.
        if grep -q "vmlinuz-$running\$" "$LCONF" && [ -d "$MODD/$running" ]; then
            ok "running kernel $running: menu entry + module tree"
        else
            err "running kernel $running is not fully bootable (no menu entry or no modules)"; drift=1
        fi

        # 7. Leftovers. Drift by request: this machine is kept clean rather than
        #    hoarding fallbacks. The RUNNING kernel is never a leftover even when
        #    its package is gone -- that is the window between a depclean and the
        #    next reboot, and calling it removable there would be advice that
        #    bricks the machine.
        local inst boot_gens leftover=""
        inst=$(qlist -Iv sys-kernel/gentoo-kernel-bin 2>/dev/null | sed 's|.*gentoo-kernel-bin-||')
        boot_gens=$(ls -1 "$BOOTD"/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||; s|\.old$||' | sort -u)
        for g in $boot_gens; do
            [ "$g" = "$running" ] && continue
            printf '%s\n' "$inst" | grep -qxF "${g%-gentoo-dist-bin}" || leftover="$leftover $g"
        done
        if [ -n "$leftover" ]; then
            warn "kernel generations in /boot that no installed package backs:"
            printf '      %s\n' $leftover
            info "      doas eclean-kernel --all --no-bootloader-update"
            info "      doas /etc/kernel/postinst.d/95-limine.install   # prunes the ESP too"
            drift=1
        else
            ok "no leftover kernel generations"
        fi
        info "ESP $(df -h --output=used,size,pcent "$ESPDIR" 2>/dev/null | tail -1 \
            | awk '{printf "%s of %s (%s)", $1, $2, $3}')"
    fi

    # ── Clock ──────────────────────────────────────────────────────
    # History, because the numbers this prints only make sense with it. From
    # ~2026-07-23 to 2026-08-05 the RTC handed the kernel a date exactly
    # 367.678 days in the past at every boot, and no Linux-side write could fix
    # it. Root cause (researched 2026-08-05): on Surfaces the CMOS RTC that
    # rtc_cmos reads and chrony's rtcsync writes is a VOLATILE DECOY -- the
    # firmware re-seeds it at power-on from the real persistent clock, an ACPI
    # Time and Alarm Device ("SRTC", ACPI000E). Linux cannot write that device:
    # acpi_tad refuses to bind ("Missing _PRW", still true on 6.18.39; see
    # linux-surface issues #415/#1497). The TAD had been reset to the FIRMWARE
    # BUILD DATE (bios_date 07/21/2025 -- the bad boots all started at
    # 2025-07-21T12:00, noon on the build date) by some power event during the
    # 2026-07 install week. Fixed by setting the clock in the Surface UEFI's
    # Date and Time page (atlas-firmware-setup gets you there), which edits the
    # real clock. One write, permanent -- the TAD ticks correctly.
    #
    # swclock predates that diagnosis and STAYS: the TAD reset once and can
    # reset again (firmware update, deep battery drain), and swclock is why the
    # year-long version of this was a curiosity instead of a problem. It is
    # invisible when it works, so this step asserts it is intact and prints
    # the measured RTC offset. The offset is never drift -- what would be
    # drift is the mitigation quietly going away.
    step "clock (RTC vs swclock mitigation)"
    local STAMP="${SWCLOCK_STAMP:-/var/lib/misc/openrc-shutdowntime}"
    local rtc_boot now_s boot_s off tz_off
    rtc_boot=$(grep -ah 'setting system clock' /var/log/kern.log 2>/dev/null \
               | tail -1 | grep -oE '\([0-9]+\)' | tr -d '()')
    if [ -n "$rtc_boot" ]; then
        now_s=$(date +%s); boot_s=$(( now_s - $(awk '{print int($1)}' /proc/uptime) ))
        off=$(( boot_s - rtc_boot ))
        # The kernel always interprets the RTC as UTC, so an RTC that actually
        # holds LOCAL time shows up as an offset equal to the UTC gap. Seen
        # 2026-08-05: the Surface UEFI's Date and Time page stores what you
        # type verbatim, so typing local time leaves exactly this signature.
        tz_off=$(date +%z | awk '{s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2); m=substr($0,4,2); print -s*(h*3600+m*60)}')
        if [ "${off#-}" -lt 300 ]; then
            ok "RTC was accurate at boot (${off}s off) — swclock had nothing to correct"
        elif [ "$(( off - tz_off ))" -lt 300 ] && [ "$(( off - tz_off ))" -gt -300 ]; then
            warn "RTC appears to hold LOCAL time ($(( (off + 1800) / 3600 ))h off at boot)"
            info "      harmless while swclock runs, but the kernel reads the RTC as UTC —"
            info "      set the UEFI clock to UTC: atlas-firmware-setup, then enter UTC time"
        elif [ "${off#-}" -lt 86400 ]; then
            info "RTC was $(( (off + 1800) / 3600 ))h off at boot — swclock corrected it"
        else
            info "RTC was $(( off / 86400 )) days off at boot — the TAD has reset again; see comment above"
        fi
    else
        info "no RTC line in /var/log/kern.log (rotated?) — offset not measured"
    fi
    # The mitigation itself. Both halves matter: swclock supplies the boot
    # clock, and its stamp is what it reads. With the stamp gone it falls back
    # to /sbin/openrc-run's mtime, which is the openrc merge date -- silently
    # putting the boot clock weeks out instead of seconds.
    if rc-update show boot 2>/dev/null | grep -qw swclock; then
        if [ -f "$STAMP" ]; then
            ok "swclock enabled, stamp present ($(date -d "@$(stat -c %Y "$STAMP")" '+%Y-%m-%d %H:%M' 2>/dev/null))"
        else
            err "swclock enabled but $STAMP is MISSING — boot clock falls back to openrc's merge date"
            info "      doas touch $STAMP    (it maintains itself from the next shutdown on)"
            drift=1
        fi
    else
        err "swclock NOT in the boot runlevel — nothing corrects the RTC, boot clock will be ~a year out"
        info "      doas rc-update add swclock boot"
        drift=1
    fi

    step "pending portage config"
    local cfgs; cfgs=$(find /etc/portage -name '._cfg*' 2>/dev/null | head)
    if [ -n "$cfgs" ]; then
        warn "unmerged ._cfg files — review before dispatch-conf, they can be STALE:"
        printf '      %s\n' $cfgs; drift=1
    else ok "no unmerged ._cfg files"; fi

    echo
    if [ "$drift" = "0" ]; then ok "machine healthy"
    else warn "problems found — each item above names its own fix"; fi
    # Return it, do not just print it. Until 2026-08-05 --check exited 0
    # unconditionally, so `./install.sh --check && deploy` ran the deploy on a
    # drifted machine and every "exit 0" ever quoted as proof of cleanliness
    # proved only that the script had finished.
    return "$drift"
}

# ── --check-rebuild: could a clean checkout actually build this? ─
# The question --check cannot answer. It asks portage to resolve @world from
# scratch (--emptytree) and report every keyword or USE change that would be
# needed, without writing any of them (--autounmask-only, and
# --autounmask-continue=n so it refuses rather than proceeding).
#
# Deliberately NOT part of --check: this takes ~25s against --check's ~4s, and
# a check slow enough to avoid running is worse than one that is honest about
# its scope. --check now points here instead.
#
# Why the whole closure rather than the declared atoms: a per-atom
# `portageq best_visible` loop over the sets costs the same 25s and misses
# dependencies. It found twelve undeclared keywords and could not have found
# gui-libs/gtk4-layer-shell (pulled in by ghostty[wayland]) or the
# libxkbcommon[X] USE flag that obs-studio needs through qtbase[gui].
run_check_rebuild() {
    banner "atlas / rebuild check" "can a clean checkout build this machine?"
    if ! have emerge; then err "emerge not available"; return 1; fi

    step "resolving @world from scratch"
    info "this takes ~25 seconds and changes nothing"
    local out rc=0
    out=$(emerge --pretend --emptytree --autounmask --autounmask-only \
                 --autounmask-continue=n @world 2>&1)

    if printf '%s\n' "$out" | grep -q "keyword changes are necessary"; then
        err "UNDECLARED KEYWORDS — a clean checkout would fail or autounmask these:"
        printf '%s\n' "$out" | sed -n '/keyword changes are necessary/,/^$/p' \
            | grep -E '^[<>=~]?[a-z0-9-]+/' | sed 's/^/      /'
        info "      add them to system/portage/package.accept_keywords/atlas"
        rc=1
    fi
    if printf '%s\n' "$out" | grep -q "USE changes are necessary"; then
        err "UNDECLARED USE FLAGS — autounmask writes keywords but never USE, so"
        err "  these fail dependency resolution instantly on a clean checkout:"
        printf '%s\n' "$out" | sed -n '/USE changes are necessary/,/^$/p' \
            | grep -E '^[<>=~]?[a-z0-9-]+/' | sed 's/^/      /'
        info "      add them to system/portage/package.use/atlas"
        rc=1
    fi
    if printf '%s\n' "$out" | grep -q "have been masked"; then
        err "MASKED PACKAGES in the dependency graph:"
        printf '%s\n' "$out" | grep -E '^- .*masked by' | sed 's/^/      /'
        rc=1
    fi

    if [ "$rc" = "0" ]; then
        local nbin nsrc
        nbin=$(printf '%s\n' "$out" | grep -cE '^\[binary')
        nsrc=$(printf '%s\n' "$out" | grep -cE '^\[ebuild')
        ok "full closure resolves: $nbin binary + $nsrc source = $((nbin + nsrc)) packages"
        ok "the repo can rebuild this machine"
    else
        echo
        warn "the repo can NOT rebuild this machine as it stands"
    fi
    return 0
}

SELECTED=()
for arg in "$@"; do
    case "$arg" in
        --check) run_check; exit $? ;;
        --check-rebuild) run_check_rebuild; exit 0 ;;
        --harvest) run_harvest; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        --list) printf '%s\n' "${ORDER[@]}"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        packages|flatpaks|apps|vendored|ai|devtools|services|dotfiles|fonts|theme) SELECTED+=("$arg") ;;
        *) err "unknown argument: $arg"; usage; exit 1 ;;
    esac
done
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=("${ORDER[@]}")

if [ "$(id -u)" -eq 0 ]; then
    err "run as your normal user (cjm), not root — the script uses $SUDO for root steps."
    exit 1
fi

banner "atlas / Gentoo + MangoWM" "cobalt-glass desktop setup"
[ "$DRY_RUN" = "1" ] && warn "DRY RUN — nothing will be changed"
info "phases: ${SELECTED[*]}"

keep_auth_warm            # prompt for doas once, then refresh in the background
trap stop_auth_warm EXIT

_i=0; _n=${#SELECTED[@]}
for name in "${SELECTED[@]}"; do
    _i=$((_i + 1))
    file="$REPO_DIR/phases/${PHASE_FILES[$name]}"
    if [ ! -f "$file" ]; then err "missing phase file: $file"; continue; fi
    phase_banner "$name" "$_i" "$_n"
    # shellcheck disable=SC1090
    bash "$file"
done

banner "done" "run bin/setup-ly, then reboot"
warn "ly is NOT installed by this script — it needs a Manifest workaround:"
warn "    doas bash bin/setup-ly      (see README for why)"
ok "Super+Space launcher · Super+Return ghostty · Super+Q close · Super+Shift+E exit"
info "theme: Super+Alt+T   ·   dictation: Super+Alt+L   ·   clipboard: Super+V"
