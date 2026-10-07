#!/bin/sh
# Apply the fix to the official TitanSlim-ubuntu.img.xz without mounting (uses debugfs, no root needed).
# usage: tools/patch-image.sh TitanSlim-ubuntu.img.xz out/TitanSlim-ubuntu-lomirifix.img.xz
set -eu
IN=${1:?input .img.xz}; OUT=${2:?output .img.xz}
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
make -C "$HERE/glshim" >/dev/null
xz -dc "$IN" > "$WORK/ubuntu.img"
OV=/usr/share/halium-overlay/usr/share/ubuntu-touch-session/lsc-wrapper
RT=/usr/share/ubuntu-touch-session/lsc-wrapper
debugfs -R "cat $OV" "$WORK/ubuntu.img" > "$WORK/lsc-wrapper" 2>/dev/null
cp "$WORK/lsc-wrapper" "$WORK/lsc-wrapper.orig"
patch "$WORK/lsc-wrapper" < "$HERE/patches/lsc-wrapper.patch"
sh -n "$WORK/lsc-wrapper"
put() { # src dest mode
  { echo "rm $2"; echo "write $1 $2"; echo "set_inode_field $2 mode 0100$3"; echo "set_inode_field $2 uid 0"; echo "set_inode_field $2 gid 0"; } \
    | debugfs -w -f - "$WORK/ubuntu.img" >/dev/null 2>&1
}
put "$HERE/glshim/libglshim.so" /usr/lib/aarch64-linux-gnu/libglshim.so 755
put "$WORK/lsc-wrapper" "$OV" 755
put "$WORK/lsc-wrapper" "$RT" 755   # runtime copy; the halium-overlay copy is what gets bound at boot
e2fsck -fn "$WORK/ubuntu.img" >/dev/null
mkdir -p "$(dirname "$OUT")"
xz -T0 -9 -c "$WORK/ubuntu.img" > "$OUT"
sha256sum "$OUT"
