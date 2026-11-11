#!/bin/bash
# Build ffmpeg 9.0.2 (LibreELEC v4l2-request patch set) + mpv with ALSA output
# for the Z96A (arm64). Runs inside an arm64 Debian trixie container.
set -euo pipefail
cd /work

LE_COMMIT=a1d24cae66825c22ba2d6c6013886347a9f66081
MPV_COMMIT=1800573999b29a145de3eb303a0b51d840a6b3de
PATCH_DIRS="postproc libreelec v4l2-request detlev vf-deinterlace-v4l2m2m"

fetch_le_patches() {
	local d
	[ -d /work/le/packages/multimedia/ffmpeg/patches ] && return 0
	rm -rf /work/le
	git init -q /work/le
	cd /work/le
	git remote add origin https://github.com/LibreELEC/LibreELEC.tv
	git fetch -q --depth 1 origin "$LE_COMMIT"
	git checkout -q FETCH_HEAD -- packages/multimedia/ffmpeg/patches
	cd /work
}

build_ffmpeg() {
	if [ -x /usr/local/lib/libavcodec.so ] && [ -f /work/ffmpeg/.z96a-built ]; then
		echo "ffmpeg already built"
		return 0
	fi
	if [ ! -d /work/ffmpeg ]; then
		git clone -q --depth 1 --branch n9.0.2 https://github.com/FFmpeg/FFmpeg.git /work/ffmpeg
	fi
	fetch_le_patches
	cd /work/ffmpeg
	if [ ! -f .z96a-patched ]; then
		for d in $PATCH_DIRS; do
			for p in "/work/le/packages/multimedia/ffmpeg/patches/$d"/*.patch; do
				[ -e "$p" ] || continue
				echo "patch: $d/$(basename "$p")"
				patch -p1 -s <"$p"
			done
		done
		touch .z96a-patched
	fi
	if [ -f Makefile ]; then make clean >/dev/null 2>&1 || true; fi
	./configure \
		--prefix=/usr/local \
		--arch=aarch64 \
		--target-os=linux \
		--enable-gpl \
		--enable-version3 \
		--enable-shared \
		--disable-static \
		--disable-doc \
		--disable-programs \
		--enable-pic \
		--extra-cflags="-I/work/kernel-include" \
		--enable-v4l2-request \
		--enable-v4l2_m2m \
		--enable-libdrm \
		--enable-libudev \
		--enable-avdevice \
		--enable-avfilter \
		--enable-postproc \
		--enable-swscale \
		--enable-swresample
	# Static libs for mpv would need every transitive dependency; ship the
	# shared libraries inside the mpv package instead.
	make -j"$(nproc)"
	make install
	touch .z96a-built
	ln -sfn /usr/local/lib /work/ffmpeg-lib
	cd /work
}

build_mpv() {
	if [ -f /work/mpv/build/mpv ] && [ -f /work/mpv/.z96a-built ]; then
		echo "mpv already built"
		return 0
	fi
	if [ ! -d /work/mpv ]; then
		git init -q /work/mpv
		cd /work/mpv
		git remote add origin https://github.com/philipl/mpv
		git fetch -q --depth 50 origin "$MPV_COMMIT"
		git checkout -q FETCH_HEAD
	fi
	cd /work/mpv
	patch_mpv_meson
	rm -rf build
	PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
	meson setup build --prefix=/usr --buildtype=release \
		-Dalsa=enabled \
		-Dpulse=disabled \
		-Djack=disabled \
		-Dx11=enabled \
		-Dwayland=disabled \
		-Ddrm=enabled \
		-Dv4l2request=enabled \
		-Dvulkan=disabled \
		-Dcuda-hwaccel=disabled \
		-Dcuda-interop=disabled \
		-Dlibarchive=enabled \
		-Duchardet=enabled
	PKG_CONFIG_PATH=/usr/local/lib/pkgconfig ninja -C build
	touch .z96a-built
	cd /work
}

patch_mpv_meson() {
	# Debian trixie no longer ships sys/vt.h, which mpv uses to decide whether
	# the DRM VO exists. Keep the DRM VO gated on it, but always compile the
	# dmabuf/drmprime hwdec sources when libdrm and libdisplay-info are present
	# (the X11/EGL path needs them for v4l2request zero-copy).
	python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("/work/mpv/meson.build")
t = p.read_text()
old = """features += {'drm': drm.found() and libdisplay_info.found() and
             (features['vt.h'] or features['consio.h'] or features['wsdisplay-usl-io.h'])}
if features['drm']
    dependencies += [drm, libdisplay_info]
    sources += files('video/drmprime.c',
                     'video/out/drm_atomic.c',
                     'video/out/drm_common.c',
                     'video/out/drm_prime.c',
                     'video/out/hwdec/hwdec_drmprime.c',
                     'video/out/hwdec/hwdec_drmprime_overlay.c',
                     'video/out/vo_drm.c')
endif"""
new = """libdrm_found = drm.found() and libdisplay_info.found()
features += {'drm': libdrm_found and
             (features['vt.h'] or features['consio.h'] or features['wsdisplay-usl-io.h'])}
if libdrm_found
    dependencies += [drm, libdisplay_info]
    sources += files('video/drmprime.c',
                     'video/out/drm_common.c',
                     'video/out/drm_prime.c',
                     'video/out/hwdec/hwdec_drmprime.c',
                     'video/out/hwdec/hwdec_drmprime_overlay.c')
endif
if features['drm']
    sources += files('video/out/drm_atomic.c',
                     'video/out/vo_drm.c')
endif"""
if old in t:
    p.write_text(t.replace(old, new))
    print("mpv meson patched: drmprime sources independent of vt.h")
else:
    print("mpv meson already patched or layout changed")
PYEOF
}

build_placebo() {
	if [ -f /usr/local/lib/pkgconfig/libplacebo.pc ] && [ -f /work/libplacebo/.z96a-built ]; then
		echo "libplacebo already built"
		return 0
	fi
	if [ ! -d /work/libplacebo ]; then
		git clone -q --depth 1 --branch v7.387.0 --recurse-submodules --shallow-submodules https://github.com/haasn/libplacebo.git /work/libplacebo
	fi
	cd /work/libplacebo
	git submodule update --init --recursive
	rm -rf build
	meson setup build --prefix=/usr/local --buildtype=release \
		-Ddemos=false -Dtests=false -Dvulkan=disabled -Dshaderc=enabled -Dglslang=enabled -Dopengl=enabled
	ninja -C build
	ninja -C build install
	touch .z96a-built
	cd /work
}

build_ffmpeg
build_placebo
build_mpv
echo "BUILD OK"
