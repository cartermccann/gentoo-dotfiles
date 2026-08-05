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
  dotfiles   symlink configs into ~/.config (incl. nvim), deploy shell config
  theme      install the atlas-theme switcher and apply the default (cobalt)

Options:
  --dry-run   print what would happen, change nothing
  --check     diff the repo against the live system, change nothing (~4s)
  --check-rebuild
              resolve @world from scratch: could a CLEAN CHECKOUT build this
              machine? changes nothing (~25s)
  --list      list phases and exit
  -h, --help  this help

Examples:
  ./install.sh                 # everything, in order
  ./install.sh dotfiles        # just deploy configs
  ./install.sh --dry-run       # preview the whole run
EOF
}

# ── The system files this repo owns ────────────────────────────
# One list, two readers: the file-by-file diff below, and the stray scan that
# reports live files this repo has never heard of. Keeping it in one place is
# what stops a file being deployed but not checked, or checked but not deployed.
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
system/udev/99-worklouder.rules /etc/udev/rules.d/99-worklouder.rules
MAP
}

# ── Atoms this repo declares ───────────────────────────────────
# One place: the set files under system/portage/sets/. Portage reads the same
# files, so "declared" and "what emerge will install" cannot disagree.
declared_atoms() {
    # Declared == listed in a set file under system/portage/sets/. Nothing else
    # counts, and that is the point of the package-sets model.
    #
    # This used to scrape bash arrays and `emerge` lines out of phases/ and
    # bin/setup-*, which was a guess dressed as a check. Two ways it lied:
    # scanning comments made a package "declared" because a comment mentioned
    # it (three of the four atlas-bootstrap packages hid behind that on
    # 2026-08-05), and an `emerge --deselect` in a cleanup script had to be
    # explicitly filtered out because a removal read as a declaration.
    #
    # Reading the sets has neither problem: there is exactly one list, portage
    # reads the same file, and an inline `emerge` somewhere in a phase is now
    # correctly reported as undeclared rather than silently satisfying the diff.
    sed 's/#.*//' "$REPO_DIR"/system/portage/sets/* 2>/dev/null \
        | tr -s '[:space:]' '\n' \
        | grep -oE '^[<>=~]*[a-z][a-z0-9]*(-[a-z0-9]+)?/[a-zA-Z0-9][a-zA-Z0-9._+-]*$' \
        | sed 's/^[<>=~]*//' \
        | sed -E 's/-[0-9][a-zA-Z0-9._-]*$//' \
        | valid_categories_only \
        | sort -u
}

# A path is not an atom. `services/micro-herdr` matches the shape of a package
# perfectly, so shape alone is not enough — the category has to be a real one.
# profiles/categories is portage's own authoritative list.
valid_categories_only() {
    local cats="/var/db/repos/gentoo/profiles/categories"
    if [ -r "$cats" ]; then
        grep -F -f <(sed 's|$|/|' "$cats") -
    else
        cat    # no tree to validate against; better to over-report than to hide
    fi
}

# Every package actually merged, category/name with the version stripped.
#
# This used to read /var/lib/portage/world, which stopped meaning anything the
# moment the sets became the source of truth: the migration empties the world
# file on purpose, so a world-file read reported all 114 declared packages as
# missing. @world still resolves correctly for portage -- it expands through
# world_sets -- but that expansion is exactly the set files, so diffing the
# sets against it could only ever compare a list to itself.
#
# The package database is the honest answer to "is this actually installed?",
# which is the question the declared-but-absent check exists to ask. The
# opposite direction, installed-but-undeclared, is the --depclean --pretend
# step below and needs nothing from here.
installed_atoms() {
    find /var/db/pkg -mindepth 2 -maxdepth 2 -type d -printf '%P\n' 2>/dev/null \
        | sed -E 's/-[0-9][a-zA-Z0-9._-]*$//' \
        | sort -u
}

# ── --check: is the live system still what the repo says? ──────
# The Nix-ish property we want: the repo is the source of truth, and any
# drift is visible rather than silent.
run_check() {
    banner "atlas / config check" "repo vs live system"
    local drift=0

    step "system files (/etc)"
    while read -r src dst; do
        [ -z "$src" ] && continue
        if [ ! -f "$REPO_DIR/$src" ]; then
            # The map names a file the repo does not have. Distinct from DRIFTED:
            # nothing differs, the source of truth is simply absent, and `diff`
            # would just print "No such file or directory".
            err "NO REPO FILE  $src (mapped to $dst, but not in the repo)"; drift=1
        elif [ ! -d "$(dirname "$dst")" ]; then
            # e.g. /etc/ly before bin/setup-ly has been run.
            # Not drift — just not applicable on this machine yet.
            info "n/a      $dst (parent directory absent)"
        elif [ ! -f "$dst" ]; then
            err "MISSING  $dst"; drift=1
        elif cmp -s "$REPO_DIR/$src" "$dst"; then
            ok "in sync  $dst"
        else
            warn "DRIFTED  $dst"; drift=1
            diff -u "$dst" "$REPO_DIR/$src" | sed -n '3,12p' | sed 's/^/      /'
        fi
    done < <(system_file_map)

    step "system files: is anything deploying them?"
    # "in sync" only means the live file matches the repo. It does NOT mean any
    # phase would ever put it there. /etc/conf.d/consolefont sat in the map for
    # weeks reading "in sync" while no phase deployed it — it had been placed by
    # hand once, so a clean checkout would have silently dropped it. A mapped
    # file that nothing installs is a lie the check was telling.
    # Two ways a phase can deploy a file, so two ways to find one.
    #
    # The literal path covers deploy_system_file, which is called with the full
    # "$REPO_DIR/system/..." string. Set files are not: deploy_set takes a bare
    # name and builds the path inside lib/common.sh, so a path grep cannot see
    # them. That gap was silent rather than loud -- four of the five sets
    # matched anyway, purely because their full paths happen to appear in nearby
    # comments, and only atlas-bootstrap (mentioned nowhere by path) failed. A
    # check that passes on a comment is not checking anything.
    local orphan=0 name
    while read -r src dst; do
        [ -z "$src" ] && continue
        if grep -rqF "$src" "$REPO_DIR"/phases/ "$REPO_DIR"/bin/ 2>/dev/null; then
            continue
        fi
        # A set file is deployed iff some phase calls `deploy_set <its name>`.
        case "$src" in
            system/portage/sets/*)
                name="${src##*/}"
                if grep -rqE "deploy_set[[:space:]]+${name}([[:space:]]|\$)" \
                        "$REPO_DIR"/phases/ "$REPO_DIR"/bin/ 2>/dev/null; then
                    continue
                fi ;;
        esac
        err "NOT DEPLOYED  $src is checked but no phase or bin/ script installs it"
        orphan=1; drift=1
    done < <(system_file_map)
    [ "$orphan" = "0" ] && ok "every mapped system file has something that deploys it"

    step "user configs (~/.config -> repo)"
    for d in "$REPO_DIR"/config/*/; do
        local n dst; n=$(basename "$d"); dst="$HOME/.config/$n"
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$d")" ]; then
            ok "linked   ~/.config/$n"
        elif [ -e "$dst" ]; then
            warn "NOT A LINK  ~/.config/$n (local copy shadows the repo)"; drift=1
        else
            err "MISSING  ~/.config/$n"; drift=1
        fi
    done

    step "services"
    while read -r svc lvl; do
        case "$svc" in ""|\#*) continue ;; esac
        if ! [ -f "/etc/init.d/$svc" ]; then err "no init script: $svc"; drift=1
        elif rc-update show "$lvl" 2>/dev/null | grep -qw "$svc"; then ok "$svc -> $lvl"
        else warn "NOT ENABLED  $svc ($lvl)"; drift=1; fi
    done < "$REPO_DIR/system/services.conf"

    step "user services (s6)"
    local scan="$HOME/.local/state/s6/scan"
    if [ ! -d "$scan" ]; then
        info "n/a      no scan directory — './install.sh services' has not run"
    else
        # Whether a supervisor is alive has to be established FIRST, because
        # s6's control fifo outlives the supervisor that made it. Testing only
        # for the fifo reports "supervised" for a service that has not been
        # running since the last time a tree happened to be started — which is
        # exactly the silent failure this check exists to catch.
        local sup_up=0
        pgrep -u "$USER" -x s6-svscan >/dev/null 2>&1 && sup_up=1
        if [ "$sup_up" = "0" ]; then
            info "supervisor not running — it starts with the graphical session"
        fi
        for d in "$REPO_DIR"/services/*/; do
            [ -f "$d/run" ] || continue      # README.md is not a service
            local n dst; n=$(basename "${d%/}"); dst="$scan/$n"
            if [ ! -L "$dst" ]; then
                err "MISSING  $n (not linked into the scan directory)"; drift=1
            elif [ "$(readlink -f "$dst")" != "$(readlink -f "${d%/}")" ]; then
                warn "DRIFTED  $n (links somewhere other than the repo)"; drift=1
            elif [ "$sup_up" = "0" ]; then
                # Correct on disk, nothing supervising it. Not drift: outside a
                # session this is the expected state.
                info "linked   $n (defined, not running)"
            elif s6-svstat "$dst" 2>/dev/null | grep -q '^up'; then
                # s6 measures uptime from the timestamp it recorded when the
                # service started, so a clock STEP after that point corrupts the
                # figure. On 2026-07-26 both services reported ~31,768,515
                # seconds (367 days) on a machine that had been up 18 minutes:
                # the RTC read 2025-07-24 at boot, s6 stamped against that, then
                # chronyd stepped the clock forward a year.
                #
                # A service cannot have been running longer than the machine has
                # been up, so /proc/uptime is the ceiling. Reporting "unknown" is
                # the point of this: the number exists to distinguish "up since
                # login" from "restarted an hour ago", and a wrong number answers
                # that question confidently and incorrectly.
                local svstat sv_secs sys_secs
                svstat=$(s6-svstat "$dst" 2>/dev/null)
                sv_secs=$(printf '%s' "$svstat" | grep -oE '[0-9]+ seconds' | grep -oE '^[0-9]+')
                sys_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
                if [ -n "$sv_secs" ] && [ -n "$sys_secs" ] && [ "$sv_secs" -gt "$sys_secs" ]; then
                    ok "up       $n  (age unknown — start time predates boot, clock stepped after s6 started)"
                else
                    ok "up       $n  ($svstat)"
                fi
            else
                warn "DOWN     $n  ($(s6-svstat "$dst" 2>&1 | head -1))"; drift=1
            fi
        done
    fi

    step "undeclared portage config"
    # The file-by-file comparison above only sees files this repo already knows
    # about, so anything ELSE under /etc/portage is invisible to it — including
    # what portage's own --autounmask-write drops there mid-emerge.
    #
    # Four such files were found under package.* on 2026-07-26 (zz-autounmask,
    # system, webkit-gtk, zen-bin), all load-bearing. Then three MORE turned up
    # at the top level, which this scan originally did not reach at all:
    # make.conf (MAKEOPTS, march, FEATURES=getbinpkg), repos.conf (the GURU
    # overlay URI, without which swaync and sd do not exist) and binrepos.conf
    # (the x86-64-v3 binhost — without it this is a from-source machine). A
    # clean checkout reproduced none of them. Listing strays is how that stops
    # being a once-a-year discovery.
    local stray=0 f known pkg
    known=$(system_file_map | awk '{print $2}')
    while read -r f; do
        [ -n "$f" ] || continue
        # Files the repo deploys are diffed above, not reported here.
        printf '%s\n' "$known" | grep -qxF "$f" && continue
        # savedconfig: portage writes one of these whenever an ebuild that
        # SUPPORTS USE=savedconfig is merged, whether or not the flag is on.
        # sys-kernel/linux-firmware drops a 6700-line, 227 KB list of every
        # firmware blob, version-stamped, so it is regenerated under a new name
        # on every single bump -- tracking it would mean drift after every
        # firmware update forever.
        #
        # But NOT a blanket exclusion. With USE=savedconfig enabled the file is
        # real configuration: it decides which blobs get installed, and an
        # untracked one would be exactly the kind of undeclared, load-bearing
        # state this scan exists to find. So the flag decides. Off means inert
        # template, skip; on means config, report it.
        case "$f" in
            /etc/portage/savedconfig/*)
                pkg="${f#/etc/portage/savedconfig/}"          # cat/pkg-version
                pkg="${pkg%-[0-9]*}"                           # strip version
                if ! tr ' ' '\n' < /var/db/pkg/"$pkg"-*/USE 2>/dev/null \
                        | grep -qx savedconfig; then
                    continue
                fi
                warn "UNDECLARED  $f (USE=savedconfig is ON — this file is live config)"
                stray=1; drift=1; continue ;;
        esac
        case "$(basename "$f")" in
            # The installer's own displaced copies. They live in
            # CONFIG_BACKUP_DIR now (see lib/common.sh), but old ones linger.
            *.bak.*)
                warn "STALE BACKUP  $f — safe to delete"; stray=1; drift=1; continue ;;
            *autounmask*)
                warn "AUTOUNMASK  $f — portage wrote this during an emerge"
                info "      fold the entries into system/portage/ and delete it"
                stray=1; drift=1; continue ;;
        esac
        warn "UNDECLARED  $f (not owned by the repo)"
        stray=1; drift=1
    done < <({ find /etc/portage/package.use /etc/portage/package.accept_keywords \
                    /etc/portage/package.license /etc/portage/package.mask \
                    -maxdepth 1 -type f 2>/dev/null
               # Top-level and the directories portage reads wholesale. Excludes
               # gnupg/ (binpkg keyring, portage's own state) and make.profile
               # (an eselect-managed symlink, not a config file).
               find /etc/portage -maxdepth 1 -type f 2>/dev/null
               find /etc/portage/repos.conf /etc/portage/binrepos.conf \
                    /etc/portage/env /etc/portage/sets /etc/portage/savedconfig \
                    -type f 2>/dev/null
             } | sort -u)
    [ "$stray" = "0" ] && ok "every /etc/portage file is repo-owned"

    step "packages (declared vs installed)"
    # Asks one thing: does every atom the sets declare actually exist on disk?
    # A miss is a typo'd atom or a package that failed to merge and was never
    # chased down -- both invisible any other way, because a set file is just
    # text and nothing validates it against the tree.
    #
    # The reverse question ("is anything installed that no set declares?") is
    # NOT asked here. It belongs to --depclean --pretend below, which answers it
    # from portage's own dependency graph and therefore knows the difference
    # between an undeclared package and a legitimate dependency. This check has
    # no such knowledge: every one of the 907 installed packages that is merely
    # a dependency would look undeclared to it.
    local missing_pkgs
    missing_pkgs=$(comm -23 <(declared_atoms) <(installed_atoms))
    if [ -n "$missing_pkgs" ]; then
        warn "$(printf '%s\n' "$missing_pkgs" | wc -l) declared in a set but NOT installed:"
        printf '      %s\n' $missing_pkgs
        info "      typo in the atom, or the merge failed — check ~/.cache/atlas-emerge.log"
        drift=1
    else
        ok "every declared package is installed"
    fi

    step "services (enabled vs declared)"
    # The loop above asks "is what the repo declares enabled?" — the opposite
    # question, "is anything else enabled?", went unasked. docker, sshd, chronyd
    # and sysklogd were all live and undeclared on 2026-07-26.
    #
    # BASELINE is the stage3 + profile set: services OpenRC brings up on its own,
    # which this repo neither enables nor should have to declare. Anything in
    # boot/default that is neither baseline nor declared is drift.
    #
    # hwclock is deliberately NOT in this list even though it is a stock
    # service. This machine runs swclock instead (system/services.conf has the
    # RTC story), and the two conflict -- both `provide clock`. Left in
    # BASELINE, hwclock could be re-enabled and silently restore the
    # year-behind boot clock while every check here still reported green.
    # Outside BASELINE, its return is drift and gets reported.
    local BASELINE="binfmt bootmisc fsck hostname keymaps local
        localmount loopback modules mtab netmount procfs root save-keymaps
        save-termencoding seedrng swap sysctl systemd-tmpfiles-setup
        termencoding"
    local declared_svcs extra_svcs=""
    declared_svcs=$(sed 's/#.*//' "$REPO_DIR/system/services.conf" | awk '{print $1}')
    for lvl in boot default; do
        while read -r svc; do
            [ -n "$svc" ] || continue
            printf '%s\n' $BASELINE | grep -qxF "$svc" && continue
            printf '%s\n' $declared_svcs | grep -qxF "$svc" && continue
            extra_svcs="$extra_svcs $svc($lvl)"
        done < <(rc-update show "$lvl" 2>/dev/null | awk '{print $1}')
    done
    if [ -n "$extra_svcs" ]; then
        warn "enabled but declared nowhere:$extra_svcs"
        info "      add to system/services.conf with the reason, or disable"
        drift=1
    else
        ok "no undeclared services enabled"
    fi

    step "removable packages (--depclean --pretend)"
    # THE REVERSE DIRECTION. Every other check here asks "is what the repo
    # declares present?". This asks "is anything present that the repo does not
    # declare?" — the question that had no answer at all before package sets, because
    # `emerge --noreplace` only ever adds. Deleting an atom from a bash array
    # left the package installed forever and nothing noticed.
    #
    # Read-only: --pretend never removes anything. Acting on it is deliberate
    # and manual, by design — a wrong set file plus an automatic
    # depclean is how you uninstall your own bootloader.
    if ! have emerge; then
        info "emerge not available — skipping"
    elif [ ! -s /var/lib/portage/world_sets ]; then
        # Until the sets are registered, world still holds ~113 individual
        # atoms and depclean protects all of them, so a clean result here would
        # mean nothing. Say that rather than printing a reassuring "0".
        warn "world_sets is empty — the package-sets migration has not been run"
        info "      until then the world file, not the sets, is the source of truth"
        info "      migration steps: ~/projects/wargames/atlas-cleanup/DECISIONS.md"
    else
        # The world file must stay EMPTY. Every atom this machine wants is
        # declared in a set, and the sets are what world_sets registers, so
        # anything landing in world came from a bare `emerge <atom>` -- portage
        # adds to world unless told --oneshot. That atom is then a depclean root
        # in its own right, which quietly defeats the whole model: delete it
        # from its set file and depclean will still protect it forever.
        #
        # Added 2026-08-05 after `emerge --newuse app-admin/eclean-kernel`
        # (missing --oneshot) recorded it in world, and the check ran green
        # anyway. It also turned up gui-apps/wl-clipboard, which had been
        # sitting there since before the migration while declared in
        # atlas-core:103 -- invisible to every other check here.
        if [ -s /var/lib/portage/world ]; then
            local w_declared w_undeclared
            w_declared=$(comm -12 <(sort -u /var/lib/portage/world) <(declared_atoms))
            w_undeclared=$(comm -23 <(sort -u /var/lib/portage/world) <(declared_atoms))
            warn "world file is not empty — every atom belongs in a set, not world"
            [ -n "$w_declared" ] && {
                printf '      %s\n' $w_declared
                info "      ^ already declared in a set; the world entry is redundant:"
                info "        doas emerge --deselect <atom>"
            }
            [ -n "$w_undeclared" ] && {
                printf '      %s\n' $w_undeclared
                info "      ^ declared NOWHERE; add to a set file, then --deselect"
            }
            info "      installing by hand? use: doas emerge --oneshot <atom>"
            drift=1
        else
            ok "world file empty — the sets are the only source of truth"
        fi

        local removable
        removable=$(emerge --depclean --pretend --quiet 2>/dev/null \
            | grep -oE '^[[:space:]]*[a-z0-9-]+/[a-zA-Z0-9._+-]+' | tr -d ' ')
        if [ -n "$removable" ]; then
            # Two very different things end up in this list, and conflating them
            # sends you the wrong way. A package that no set declares is drift:
            # declare it or remove it. A package that IS declared is an old SLOT
            # of something still wanted -- a superseded kernel, say -- and the
            # fix is never "add it to a set", it is deciding whether the old slot
            # has earned its keep. Reported separately since 2026-08-05, when a
            # kernel bump made this print "sys-kernel/gentoo-kernel-bin declared
            # in no set" about an atom sitting in atlas-core line 25.
            local undeclared_removable declared_removable
            undeclared_removable=$(comm -23 <(printf '%s\n' $removable | sort -u) <(declared_atoms))
            declared_removable=$(comm -12 <(printf '%s\n' $removable | sort -u) <(declared_atoms))
            if [ -n "$undeclared_removable" ]; then
                warn "$(printf '%s\n' "$undeclared_removable" | wc -l) installed, declared in no set:"
                printf '      %s\n' $undeclared_removable
                info "      declare it in system/portage/sets/, or remove it with:"
                info "        doas emerge --depclean --ask   (read the list first)"
                # Only THIS branch is drift. The superseded-slot branch below
                # prints "not drift" and used to set this flag anyway, so a
                # freshly-updated kernel left --check red until the old slot was
                # depcleaned -- a check contradicting its own output, which
                # teaches you to stop reading the output.
                drift=1
            fi
            if [ -n "$declared_removable" ]; then
                warn "$(printf '%s\n' "$declared_removable" | wc -l) superseded version(s) of a DECLARED package:"
                printf '      %s\n' $declared_removable
                info "      not drift — a newer slot is installed and the old one is now spare."
                info "      For a kernel, do NOT remove it until you have booted the new one:"
                info "        uname -r        # what you are running right now"
                info "        emerge --depclean --pretend sys-kernel/gentoo-kernel-bin"
            fi
        else
            ok "nothing installed that the sets do not declare"
        fi
    fi

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

    step "pending portage config"
    local cfgs; cfgs=$(find /etc/portage -name '._cfg*' 2>/dev/null | head)
    if [ -n "$cfgs" ]; then
        warn "unmerged ._cfg files — review before dispatch-conf, they can be STALE:"
        printf '      %s\n' $cfgs; drift=1
    else ok "no unmerged ._cfg files"; fi

    echo
    if [ "$drift" = "0" ]; then ok "system matches the repo"
    else warn "drift found — './install.sh packages' redeploys system files"; fi
    # Say what was NOT checked. Every step above inspects the RUNNING system,
    # and on 2026-08-05 all of them passed on a machine the repo could not have
    # rebuilt: fourteen keyword/USE lines were undeclared, and the packages were
    # already merged so nothing here could see it. "system matches the repo" is
    # a narrower claim than it sounds, and saying so is cheaper than letting the
    # output overclaim for another few months.
    info "not checked here: whether the repo can REBUILD this machine"
    info "  that resolves the full dependency closure and takes ~25s:  ./install.sh --check-rebuild"
    return 0
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
        --check) run_check; exit 0 ;;
        --check-rebuild) run_check_rebuild; exit 0 ;;
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
