# User services

OpenRC has no equivalent of `systemd --user`. Its runlevels are system-wide and
root-owned, which is the wrong shape for things that belong to a graphical
session: they need the session's D-Bus address, its Wayland socket and its
PipeWire connection, and they should die with the session rather than outlive
it.

So the session gets its own supervision tree, built on **s6**.

```
services/<name>/run        the service
services/<name>/log/run    where its output goes
services/<name>/down       optional — present means "do not start automatically"
```

`phases/35-services.sh` symlinks each directory here into the scan directory at
`~/.local/state/s6/scan`, and `config/mango/autostart.sh` starts one
`s6-svscan` over it when the session comes up. s6 then keeps every service
running, restarts it when it dies, and never gives up.

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

Make a directory here with an executable `run` that **execs** the daemon in the
foreground — s6 supervises the process it starts, so a `run` that forks and
returns leaves s6 supervising nothing. Copy the `log/run` from a neighbour.
Then re-run `./install.sh services`.

Logs land in `~/.local/state/s6/log/<name>/current`, rotated by `s6-log`. They
are deliberately outside the repo: they are state, not configuration.
