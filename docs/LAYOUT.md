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
| portage (system) | `phases/10-packages.sh` → `CORE`, `TOOLS` | the desktop, CLI, languages |
| portage (apps) | `phases/25-apps.sh` → `APPS` | GUI software Gentoo packages |
| flatpak | `phases/20-flatpaks.sh` | GUI software Gentoo does not package |
| vendored | `phases/27-vendored.sh` | prebuilt bundles nobody packages |
| language runtimes | `phases/30-ai-tools.sh` | npm/cargo/go/uv installs |
| fonts | `phases/45-fonts.sh` | typefaces not in the tree |

If you install something and it is not in one of those lists, the next machine
will not have it and `./install.sh --check` will not miss it. That is the whole
contract.

## What is deployed, and how

| repo path | goes to | mechanism | why |
|---|---|---|---|
| `system/` | `/etc/...` | **copied** | /etc decides what root emerges. Pointing it at a user-writable checkout would be privilege escalation |
| `config/` | `~/.config/<app>` | **symlinked** | user-owned, so editing the repo edits the live config with no redeploy |
| `services/` | `~/.local/state/s6/scan/<name>` | **symlinked** | same reasoning as config |
| `bin/` | `~/.local/bin/<tool>` | **symlinked** | `atlas-theme`, `atlas-svc`, `atlas-wallpaper` |
| `share/applications/` | `~/.local/share/applications` | symlinked file-by-file | `NoDisplay` stubs that hide launcher junk |
| `share/vendored/*.in` | `~/.local/share/applications` | **rendered** | needs an absolute `$HOME` path, so it cannot be tracked verbatim |

State is never in the repo. Logs (`~/.local/state/s6/log`), caches
(`~/.cache/atlas`), and s6's control fifos are all outside it on purpose.

## Services

OpenRC has no user services, so the session runs its own s6 supervision tree.
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
