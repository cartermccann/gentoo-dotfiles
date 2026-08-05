# Where things live

NixOS gets its sense of order from one property: you can read the whole machine
out of one directory. Gentoo has no such guarantee, so this repo imposes it by
hand. That only works if the rules are written down, because the moment
"where does this go?" becomes a judgment call, the answer stops being
consistent and the machine stops feeling like one system.

## The two questions

**Do you edit it, or do you run it?**

| | |
|---|---|
| `~/projects/` | source you edit — git checkouts, one directory per repo |
| `~/apps/` | binaries you run — nothing here is edited, nothing is built here |

The Codex desktop bundle was originally unpacked inside
`~/projects/input-linux/`, because that is where the tool that built it lived.
That made an 800 MB blob look like a project. It is at `~/apps/codex-desktop`
now.

There is no third directory. `~/Tools/` existed for a while holding exactly one
git checkout (`comcreate-brain-mcp`), which is a project by this table's own
definition — source you edit. It moved to `~/projects/comcreate-brain-mcp` on
2026-07-26 and `~/Tools` is gone. If a path does not answer "edit or run?", it
does not get its own directory; it goes in whichever of the two it actually is.

Moving a checkout is not free: something usually points at the old path. In that
case it was one MCP server entry in `~/.claude.json`, which had to be updated in
the same change or the server would have failed to start with no obvious cause.

**Who decides what it is — you, or a package manager?**

Everything installed on this machine arrives through exactly one of six
channels, and each one is declared in exactly one place:

| channel | declared in | for |
|---|---|---|
| portage (system) | `system/portage/sets/atlas-core`, `atlas-tools` | the desktop, CLI, languages |
| portage (apps) | `system/portage/sets/atlas-apps` | GUI software Gentoo packages |
| portage (dev CLIs) | `system/portage/sets/atlas-devtools` | cloud/API/container CLIs with ebuilds |
| portage (bootstrap) | `system/portage/sets/atlas-bootstrap` | git, flatpak, ly, eselect-repository |
| flatpak | `phases/20-flatpaks.sh` | GUI software Gentoo does not package |
| vendored | `phases/27-vendored.sh` | prebuilt bundles nobody packages |
| language runtimes | `phases/30-ai-tools.sh`, `phases/32-devtools.sh` | npm/cargo/go/uv installs |
| fonts | `phases/45-fonts.sh` | typefaces not in the tree |

Everything portage installs is declared in a **package set**, not in a bash
array inside a phase. The set files are real `/etc/portage/sets/` files: portage
reads the same list the repo does, and registering them in `world_sets` makes
`emerge --depclean` the removal step. That is what lets deleting a line
*uninstall* something, which an array could never express.

Each set file explains its own contents; the decision log and the one-time
migration steps are in `~/projects/wargames/atlas-cleanup/DECISIONS.md`, per
the rule in `.gitignore` that keeps notes-about-a-particular-day out of an
installer.

The sets are the **baseline a fresh machine gets** — not an obligation on this
one. Installing ad hoc is normal: `doas emerge <pkg>` puts it in the world
file, depclean respects world, done. Add an atom to a set only when a future
fresh install should include it. Nothing compares baseline to reality anymore
(`--check` is health-only since the one-time flip later the same day) —
hand-installed packages and hand-enabled services are simply the owner's
business. (Settled 2026-08-05, twice: first the repo stopped being the
machine's police — it briefly grew Nix-style world-must-be-empty ambitions
that lasted one afternoon — then it stopped owning deployed files at all and
became a pure one-time bootstrap.)

## What is seeded, and where it lives

The repo went ONE-TIME on 2026-08-05: it seeds a fresh machine and then gets
out of the way. Nothing in `$HOME` symlinks into this checkout anymore, and
the LIVE files are the source of truth for every config — edit them where
they live, like on any normal machine. `./install.sh --harvest` is the
deliberate reverse channel: it pulls the live copies back into the repo when
the seed has earned a refresh, and `git diff` shows what changed.

| repo path | seeds | live home (edit HERE) |
|---|---|---|
| `system/` | `/etc/...` | `/etc/...` — hand-edit, dispatch-conf as normal |
| `config/` | `~/.config/<app>` | `~/.config/<app>` |
| `home/` | `~/.profile`, `~/.bash_profile` | the live files |
| `services/` | `~/.config/s6/<name>` (scan dir symlinks THERE, not here) | `~/.config/s6/<name>` |
| `bin/` | `~/.local/bin/<tool>` | `~/.local/bin/<tool>` |
| `themes/` | `~/.local/share/atlas-theme/themes` | same — atlas-theme reads only this |
| `share/applications/` | `~/.local/share/applications` | the live files |
| `share/vendored/*.in` | `~/.local/share/applications` | rendered with `$HOME`, live file is truth |

Seeding copies ONLY when the destination is absent (`seed_copy` in
lib/common.sh): a phase re-run on a provisioned machine is a no-op for
anything that exists. The one exception is `system/` on a FRESH install,
where `deploy_system_file` overwrites the stage3 defaults on purpose —
which is why you do not re-run `./install.sh packages` on a machine whose
/etc you have since hand-tuned without expecting exactly that.

State is never in the repo. Logs (`~/.local/state/s6/log`), caches
(`~/.cache/atlas`), and s6's control fifos are all outside it on purpose.

## Services

The session runs its own s6 supervision tree. OpenRC *does* have user services
as of 0.62 and they are enabled on this machine — s6 is a deliberate choice,
not a workaround for a missing feature, and `services/README.md` records why
and what would change it.
System services are declared in `system/services.conf` (`<name> <runlevel>`),
session services are directories in `services/`. See `services/README.md`.

## The check

```sh
./install.sh --check
```

Health only, since the 2026-08-05 flip: the boot chain (limine.conf, the ESP
and /boot agreeing with each other), the swclock mitigation for the Surface's
decoy RTC, and unmerged `._cfg` files (diff them — they have been STALE here
before). It does not compare configs against the repo, because the repo no
longer claims to know what the live configs should say.
