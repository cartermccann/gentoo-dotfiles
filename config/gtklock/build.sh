#!/bin/sh
# Build the atlas-colormix gtklock module.
#
# Deliberately a plain gcc line rather than meson: this is one translation unit
# with no install step, and the module only has to match gtklock's ABI (checked
# at load time via module_major_version / module_minor_version in colormix.c).
#
# Re-run after editing colormix.c, then restart gtklock. Test in a nested
# compositor first -- see the note in config.ini.
set -eu

cd "$(dirname "$0")"

gcc -shared -fPIC -O2 -Wall -Wextra \
	-o colormix.so colormix.c \
	$(pkg-config --cflags --libs gtk+-3.0) \
	-lm

echo "built: $(pwd)/colormix.so"
