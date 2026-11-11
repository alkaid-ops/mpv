#!/bin/bash
# Repack the bundled mpv deb: new binary (ALSA + v4l2request) plus the shared
# ffmpeg 9 libraries it now links against, reusing the original package's
# metadata and data files.
set -euo pipefail
cd /work

ORIG=/work/orig-mpv.deb
BIN=/work/mpv/build/mpv
OUT=/work/mpv_0.41.0-2_arm64_bookworm.deb

[ -f "$ORIG" ] || { echo "missing $ORIG" >&2; exit 1; }
[ -x "$BIN" ] || { echo "missing $BIN" >&2; exit 1; }

rm -rf /work/pkg
dpkg-deb -R "$ORIG" /work/pkg

install -m 0755 "$BIN" /work/pkg/usr/bin/mpv
strip --strip-unneeded /work/pkg/usr/bin/mpv

mkdir -p /work/pkg/usr/lib/aarch64-linux-gnu
cp -a /usr/local/lib/libav*.so* /usr/local/lib/libsw*.so* \
      /usr/local/lib/libpostproc.so* \
      /usr/local/lib/aarch64-linux-gnu/libplacebo.so* \
      /work/pkg/usr/lib/aarch64-linux-gnu/

# Runtime dependencies: everything ldd reports that we do not ship ourselves.
set +e
deps_list=""
for lib in $(ldd "$BIN" | awk '{print $3}' | grep -E '^/' | \
	grep -vE '^/usr/local|libc\.so|libm\.so|libpthread|libdl\.so|librt\.so|ld-linux' | sort -u); do
	real=$(readlink -f "$lib" 2>/dev/null)
	pkg=$(dpkg -S "$real" 2>/dev/null | head -n 1 | cut -d: -f1)
	[ -n "$pkg" ] && deps_list="$deps_list $pkg"
done
set -e
deps=$(printf '%s\n' $deps_list | sort -u | paste -sd, -)
deps=${deps:-libc6}

awk -v deps="$deps" '
	/^Depends:/ { print "Depends: " deps; next }
	{ print }
' /work/pkg/DEBIAN/control > /work/pkg/DEBIAN/control.new
mv -f /work/pkg/DEBIAN/control.new /work/pkg/DEBIAN/control

dpkg-deb --build --root-owner-group /work/pkg "$OUT"
echo "packaged: $OUT"
dpkg-deb -I "$OUT" | sed -n '/Package:/,/Description:/p' | head -12
