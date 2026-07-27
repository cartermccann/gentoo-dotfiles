# system/kernel/

## `cmdline` — do not put comments in this file

`cmdline` is deployed to `/etc/kernel/cmdline` and read by
`postinst.d/95-limine.install` like this:

```sh
CMDLINE="$(tr -s '[:space:]' ' ' < "$CMDLINE_FILE" | sed 's/^ *//;s/ *$//')"
```

That collapses the **entire file** onto one line. A `#` comment would not be
stripped — it would be appended verbatim to the kernel command line of every
Limine boot entry. Keep the file to exactly one line of parameters.

Current content:

```
root=UUID=81bcd1f5-aa30-49ab-9f14-aabf6e716f94 ro rootflags=subvol=@
```

`root=UUID=` is the **btrfs filesystem** UUID, not a partition UUID, which is why
`rootflags=subvol=@` is needed alongside it. It survives full-disk encryption
unchanged: reencryption preserves the filesystem, so this UUID still resolves once
the LUKS container is open. Encryption adds `rd.luks.uuid=luks-<container UUID>`
in front of it rather than replacing anything. See
`~/projects/wargames/wargames/atlas-fde-migration.md`, Move 8.

This file was untracked until 2026-07-26. It decides whether the machine boots,
and `95-limine.install` rebuilds every boot entry from it on each kernel update.

## `postinst.d/95-limine.install`

Gentoo's `installkernel` has no limine hook, so this supplies one: it mirrors
`/boot` kernels onto the ESP at `/efi/atlas/` and regenerates `/efi/limine.conf`
from scratch on every kernel install. It refuses to write a config whose cmdline
has no `root=`, which is a deliberate safety net — it runs unattended during
`emerge`, and a plausible-looking wrong config is worse than no config.
