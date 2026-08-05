# User services

Session daemons need the session's D-Bus address, its Wayland socket and its
PipeWire connection, and they should die with the session rather than outlive
it. OpenRC's *system* runlevels are the wrong shape for that: they are
system-wide and root-owned.

So the session gets its own supervision tree, built on **s6**.

## This is no longer the only option

This file used to open by asserting that "OpenRC has no equivalent of
`systemd --user`". That stopped being true in **OpenRC 0.62**, which added
user services with an interface much like the system-wide one. atlas runs
0.63.1, `pam_openrc.so` is active in `/etc/pam.d/system-login`, and
`rc_autostart_user` is unset in `/etc/rc.conf` (so it defaults to `YES`).
Elogind supplies the `XDG_RUNTIME_DIR` they require. **OpenRC user services
are enabled on this machine right now**, and the s6 tree sits beside them
rather than in place of something missing.

s6 is still what runs `services/`, for reasons that have nothing to do with
OpenRC lacking the feature:

- **Restart-on-crash is the whole point of `micro-reconnect`.** Its job is
  recovering a BLE link that drops; a supervisor that gives up after the first
  failure is worse than none. Any replacement has to match that, not merely
  start the thing once.
- **Per-service log rotation.** Each service gets its own `s6-log` with a
  bounded on-disk size, which is why `atlas-svc log <name>` is one command.
- **The scan directory dies with the session**, because `s6-svscan` is a child
  of `config/mango/autostart.sh`. That is the property the first paragraph is
  actually about, and it is a consequence of *where* the supervisor is started,
  not of which supervisor it is.

**What would change it:** OpenRC user services earning the same confidence for
supervision and logging, or the s6 tree growing a dependency-ordering problem
that `s6-rc` would have to solve anyway. Neither is true today. Revisit
deliberately, not because this file once claimed there was no alternative.

See `news 2025-09-04-openrc-user-services` and
https://wiki.gentoo.org/wiki/OpenRC#User_services.

```
~/.config/s6/<name>/run        the service
~/.config/s6/<name>/log/run    where its output goes
~/.config/s6/<name>/down       optional — present means "do not start automatically"
```

Definitions LIVE at `~/.config/s6/<name>` (contract flipped 2026-08-05; the
directories in this repo's `services/` are only the seed a fresh machine
starts from). `phases/35-services.sh` seeds them and symlinks each one into
the scan directory at `~/.local/state/s6/scan`, and
`config/mango/autostart.sh` starts one `s6-svscan` over it when the session
comes up. s6 then keeps every service running, restarts it when it dies, and
never gives up. s6 writes its `supervise/` and `event/` runtime dirs into
`~/.config/s6/<name>/` through the scan link — that is s6's own layout,
leave it be; `--harvest` never copies it back here.

## Why supervision rather than autostart

Everything else in `autostart.sh` is fire-and-forget: launch it once, and if it
dies the session is a little worse until the next login. That is fine for a
wallpaper.

It is not fine for `micro-reconnect`, whose entire reason to exist is that the
Codex Micro re-advertises under a rotating BLE address and drops its link. A
one-shot launch of a service whose job is recovering from failure will, the
first time it fails, stop recovering from failure.

## Control

```sh
atlas-svc                      # status of every service
atlas-svc restart micro-herdr
atlas-svc stop micro-herdr
atlas-svc log micro-herdr      # tail its log
```

`atlas-svc` is a thin wrapper over `s6-svstat` / `s6-svc`; both work directly
against `~/.local/state/s6/scan/<name>` if you prefer.

## Adding a service

Make a directory at `~/.config/s6/<name>` with an executable `run` that
**execs** the daemon in the foreground — s6 supervises the process it starts,
so a `run` that forks and returns leaves s6 supervising nothing. Copy the
`log/run` from a neighbour, link it into the scan dir
(`ln -sfn ~/.config/s6/<name> ~/.local/state/s6/scan/<name>`), make its log
dir (`mkdir -p ~/.local/state/s6/log/<name>`), then `s6-svscanctl -a
~/.local/state/s6/scan`. `./install.sh --harvest` carries the definition back
into this repo so the next fresh machine gets it too.

Logs land in `~/.local/state/s6/log/<name>/current`, rotated by `s6-log`. They
are deliberately outside the repo: they are state, not configuration.
