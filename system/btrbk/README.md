# Snapshots

`btrbk.conf` is deployed to `/etc/btrbk/btrbk.conf`. Take a snapshot with:

```sh
doas btrbk run          # both subvolumes, honouring the retention policy
doas btrbk dryrun       # show what it would do, change nothing
doas btrbk list snapshots
```

Snapshots land in `/.snapshots` (subvol `@snapshots`, mounted since the install)
and are read-only.

## These are snapshots, not backups

Every snapshot is on `/dev/nvme0n1p3`, the same disk as the data. They cover a
bad emerge, a botched config, an `rm` you regret. They cover nothing that
happens to the disk. There is no `target` in the config because this machine has
no second disk to send to (blocker B1 in `~/projects/wargames/LEDGER.md`).

## Restoring one file

What you will want nine times out of ten. Snapshots are ordinary directories:

```sh
cp /.snapshots/home.<timestamp>/cjm/path/to/file ~/path/to/file
```

Verified on 2026-07-26 with a 2 MB file: deleted, restored from the snapshot,
`sha256sum` byte-identical.

## Rolling back an entire subvolume

The case after a bad update. This has NOT been executed on this machine, unlike
the file-level restore above, so read it before trusting it.

`/etc/fstab` mounts root by filesystem UUID with `subvol=@`, so rolling back
means putting a different subvolume at the name `@`. A read-only snapshot cannot
simply be renamed into place; you snapshot *from* it, which produces a writable
copy.

```sh
# 1. mount the top level (subvolid=5), where @ / @home / @snapshots all live
doas mount -o subvolid=5 /dev/nvme0n1p3 /mnt

# 2. move the current root aside. btrfs allows renaming a mounted subvolume,
#    so this works from the running system.
doas mv /mnt/@ /mnt/@.broken

# 3. writable copy of the snapshot, at the name fstab expects
doas btrfs subvolume snapshot /mnt/@snapshots/root.<timestamp> /mnt/@

# 4. reboot. Limine and /etc/kernel/cmdline need no changes: they reference the
#    filesystem UUID and subvol=@, both of which still resolve.
doas reboot

# 5. once satisfied, reclaim the space
doas btrfs subvolume delete /mnt/@.broken
```

Two things that will bite:

- **The kernel and initramfs are not in the snapshot.** They live on the ESP at
  `/efi/atlas/`, which is FAT32 and outside btrfs entirely. Rolling `@` back to
  a state that expected a different kernel does not roll the kernel back with
  it. If the rollback is meant to undo a kernel update, re-run
  `/etc/kernel/postinst.d/95-limine.install` afterwards, or pick Limine's
  "(previous)" entry, which still points at the `.old` kernel and initramfs.
- **`/home` is a separate subvolume** and is not touched by rolling back `@`.
  That is usually what you want. If it is not, repeat steps 2-3 for `@home`
  using a `home.<timestamp>` snapshot, and do it from a rescue boot rather than
  a live session with your own files open.

## What is not in the snapshots

btrfs snapshots are not recursive, so nested subvolumes appear as empty
directories:

- `/var/lib/docker` — docker's own subvolume tree. Deliberate: container layers
  are rebuildable and would otherwise dominate the snapshot size.
- `srv` — nested inside `@`.
- `/.snapshots` itself, and `/home` within the `@` snapshot.

## Retention

`snapshot_preserve_min 2d`, then `14d 8w`: nothing is deleted in its first two
days whatever else the policy says, daily snapshots for 14 days, weekly for 8
weeks. Pruning happens on each `btrbk run`, not on a timer of its own.

btrfs snapshots are copy-on-write, so an idle snapshot costs almost nothing. The
cost grows with what changes *after* it is taken, which on this machine is
dominated by `~/.cache` (8 GB and churning). If snapshot space ever becomes a
problem, excluding cache directories by making them their own subvolume is the
lever, not shortening retention.

## Scheduling

Nothing schedules this yet. btrbk ships `btrbk.timer` and `btrbk.service`, both
systemd units, and this machine is OpenRC — they are inert. There is no cron
daemon installed either. Until that is decided, snapshots are manual:
`doas btrbk run` before anything risky.
