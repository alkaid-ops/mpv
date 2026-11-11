# z96a/mpv — mpv with ALSA + V4L2 Request for Sunniwell Z96A (RK3568)

Fork of [philipl/mpv](https://github.com/philipl/mpv) carrying the small patch and
build scripts used to produce the `mpv` package shipped in the Z96A Devuan image.

Base commit: `1800573999b29a145de3eb303a0b51d840a6b3de`
(`meson: add detection logic for v4l2request support`).

## Why this fork

The image has no PulseAudio (by design) and the previously bundled mpv was built
without ALSA support, so it had no working audio output. This fork rebuilds the
same mpv feature set with `-Dalsa=enabled`, keeping hardware HEVC/H.264 decoding
through the V4L2 Request API.

## Patch

`meson.build`: on Debian trixie `sys/vt.h` no longer exists, so mpv's
`features['drm']` test fails and the dmabuf/drmprime hwdec sources were silently
dropped from the build. The patch keeps `vo_drm` gated on `vt.h` but always
compiles `video/drmprime.c`, `video/out/drm_prime.c`,
`video/out/hwdec/hwdec_drmprime*.c` when libdrm and libdisplay-info are present.

## Build inputs

| Component | Version / commit |
|---|---|
| mpv | this fork, base `1800573` |
| FFmpeg | `n9.0.2` + LibreELEC.tv patches `a1d24cae66825c22ba2d6c6013886347a9f66081` (`postproc`, `libreelec`, `v4l2-request`, `detlev`, `vf-deinterlace-v4l2m2m`) |
| kernel UAPI | `v4l2-controls.h` from the Z96A 7.2.x kernel source (adds `V4L2_CID_STATELESS_HEVC_EXT_SPS_ST_RPS`) |
| libplacebo | `v7.387.0` (`-Dvulkan=disabled -Dshaderc=enabled -Dglslang=enabled -Dopengl=enabled`) |

Build options: `-Dalsa=enabled -Dpulse=disabled -Djack=disabled -Dx11=enabled
-Dwayland=disabled -Ddrm=enabled -Dv4l2request=enabled -Dvulkan=disabled`.

## Package layout

The produced deb is the stock `mpv 0.41.0-2` package with the rebuilt binary plus
the private shared libraries it needs:

- `usr/bin/mpv`
- `usr/lib/aarch64-linux-gnu/libav*.so*`, `libsw*.so*`, `libpostproc.so*`
- `usr/lib/aarch64-linux-gnu/libplacebo.so.387`

Runtime dependency added: `libshaderc1` (linked by libplacebo).

## Verification on hardware

- `mpv --ao=help` lists `alsa`; `AO: [alsa]` opens `default` (RK817 codec).
- `Using hardware decoding (v4l2request)`, `VO: [gpu] drm_prime[nv12]`.
- 4K HEVC fullscreen, `gpu-dumb-mode=yes`: 300 frames in ~7 s (~43 fps), matching
  the previously measured 40 fps ceiling of this X11/GL path.
- 1080p H.264/HEVC: 300 frames in ~6 s.

## Reproduce

```sh
# arm64 Debian trixie container with build deps
docker run -d --name z96a-mpv --platform linux/arm64 -v "$PWD/build:/work" debian:trixie-slim sleep infinity
# install: build-essential meson ninja-build pkg-config git curl \
#   libasound2-dev libdrm-dev libudev-dev libplacebo-dev ... libshaderc-dev glslang-dev
docker exec z96a-mpv bash -lc 'cd /work && bash z96a-build/build.sh && bash z96a-build/package-mpv.sh'
```

`z96a-build/build.sh` fetches FFmpeg/libplacebo sources, applies the LibreELEC
patch set and the kernel UAPI header, builds everything and leaves
`/work/mpv_0.41.0-2_arm64_bookworm.deb`.
