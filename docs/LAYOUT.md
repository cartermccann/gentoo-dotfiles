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
fresh install should include it. `./install.sh --check` reports the difference
between baseline and reality so it stays visible, but hand-installed packages
and hand-enabled services are the owner's business, never an error — the only
things it treats as drift are the files this repo actually deploys, the boot
chain, and the clock mitigation. (Settled 2026-08-05: this repo is a bootstrap
with owned files, not a convergence system. It briefly grew Nix-style
world-must-be-empty ambitions; they lasted one afternoon.)

## What is deployed, and how

| repo path | goes to | mechanism | why |
|---|---|---|---|
| `system/` | `/etc/...` | **copied** | /etc decides what root emerges. Pointing it at a user-writable checkout would be privilege escalation |
| `config/` | `~/.config/<app>` | **symlinked** | user-owned, so editing the repo edits the live config with no redeploy |
| `home/` | `~/.profile`, `~/.bash_profile` | **symlinked** | PATH for bash login shells, which `pam_openrc` now runs at login. Symlinked so an installer appending a PATH line writes into the repo, where `git diff` shows it |
| `services/` | `~/.local/state/s6/scan/<name>` | **symlinked** | same reasoning as config |
| `bin/` | `~/.local/bin/<tool>` | **symlinked** | `atlas-theme`, `atlas-svc`, `atlas-wallpaper` |
| `share/applications/` | `~/.local/share/applications` | symlinked file-by-file | `NoDisplay` stubs that hide launcher junk |
| `share/vendored/*.in` | `~/.local/share/applications` | **rendered** | needs an absolute `$HOME` path, so it cannot be tracked verbatim |

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

Diffs every deployed file against the repo, confirms `~/.config` entries are
still symlinks and not local copies that silently shadow the repo, confirms
system services are enabled and session services are linked and supervised, and
flags unmerged `._cfg` files. Anything it reports is drift; drift is either a
change worth committing or a mistake worth reverting, and both are better than
not knowing.
