# scx scheds for debian sid

Debian packages for [sched_ext](https://github.com/sched-ext/scx) CPU
schedulers, built from upstream release tags inside a container and published
through GitHub Releases.

Two binary packages are produced:

| Package | Contents |
|---|---|
| `scx` | The schedulers themselves (`scx_lavd`, `scx_bpfland`, `scx_rusty`, ...) plus a simple `scx.service` driven by `/etc/default/scx` |
| `scx-loader` | The `scx_loader` D-Bus daemon with its `scxctl` CLI and `scxtui` TUI, configured via `/etc/scx_loader.toml` |

Both systemd units ship **disabled** — nothing starts or switches your CPU
scheduler until you opt in.

**Supported platform: Debian sid (unstable) only.** Binaries are linked
against the current sid glibc and are not expected to work on stable or older
distributions. You also need a kernel with sched_ext support (>= 6.12, built
with `CONFIG_SCHED_CLASS_EXT`; e.g. XanMod).

## Installing

Download the `.deb` files from the [releases page](../../releases) (release
`scx-v<version>` contains everything), then:

```sh
sudo apt install ./scx_<version>-1_amd64.deb
# optional, for scxctl/scxtui:
sudo apt install ./scx-loader_<version>-1_amd64.deb
```

Runtime dependencies are minimal (libc, libelf, libseccomp, zlib — libbpf is
linked statically).

## Configuring

Pick **one** of the two mechanisms below; they both work, just don't run them
at the same time.

### Option A: `scx.service` (simple, no daemon)

Edit `/etc/default/scx`:

```sh
SCX_SCHEDULER=scx_lavd
# SCX_FLAGS="--autopilot"        # extra flags passed to the scheduler
```

Any scheduler installed under `/usr/sbin/scx_*` can be used. Check
`scx_lavd --help` for available flags.

### Option B: `scx_loader` (D-Bus daemon + `scxctl`)

Edit `/etc/scx_loader.toml`:

```toml
default_sched = "scx_lavd"
default_mode  = "Auto"     # Auto | Gaming | LowLatency | PowerSave | Server

# per-scheduler flags per mode:
# [scheds.scx_lavd]
# gaming_mode = ["--performance"]
```

`scxctl list` shows the schedulers the loader knows about. Note that a few
in-tree schedulers (`scx_layered`, `scx_mitosis`) are not wired into the
loader and are only available through option A.

## Starting

```sh
# Option A:
sudo systemctl enable --now scx

# Option B:
sudo systemctl enable --now scx_loader
scxctl get          # current scheduler + mode
scxctl list         # schedulers supported by the loader
scxctl switch scx_bpfland
scxctl stop
scxtui              # interactive TUI (scheduler list, status, logs)
```

For a quick test without any service, just run a scheduler in the foreground;
`Ctrl-C` returns you to the kernel's default scheduler:

```sh
sudo scx_lavd --monitor 5
```

Useful status checks:

```sh
cat /sys/kernel/sched_ext/state   # enabled / disabled + loaded ops
systemctl status scx              # or scx_loader
journalctl -u scx_loader -b       # loader/scheduler logs
```

## Building locally

Requires `podman` or `docker`; nothing is installed on the host.

```sh
./build.sh                              # versions pinned in the changelogs
SCX_VERSION=1.1.4 ./build.sh            # track a specific scx release
SCX_VERSION=latest LOADER_VERSION=latest ./build.sh
```

Artifacts land in `out/` — one `.deb` per source package. The container
fetches upstream sources at build time, vendors all Rust crates for offline
builds, and runs `dpkg-buildpackage` with
`DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$(nproc)"`, i.e. tests
skipped and no `-dbgsym` packages. Set `DEB_BUILD_OPTIONS` yourself to
change that (dropping `noautodbgsym` brings the debug symbol packages back).

## CI / releases

`.github/workflows/build-deb.yml`:

- **weekly schedule** — checks both upstream repos for new release tags and
  publishes a GitHub Release (`scx-v<version>`) with the debs if the newest
  version hasn't been released yet;
- **tag push** `v*` — builds that scx version and publishes;
- **workflow_dispatch** — manual run with version inputs; set the `release`
  checkbox to publish.

## Repository layout

```
packaging/scx/        debian/ packaging for the schedulers (source: sched-ext/scx)
packaging/scx-loader/ debian/ packaging for the loader (source: sched-ext/scx-loader)
scripts/prepare-source.sh   clone tag -> cargo vendor -> orig tarball -> overlay packaging/
Containerfile        debian:sid build environment (shared by local builds and CI)
build.sh             local build wrapper (podman or docker)
```

## Notes

- Packaging is derived from
  [sched-ext/scx-scheds-packaging-deb](https://github.com/sched-ext/scx-scheds-packaging-deb),
  adapted for the Debian toolchain: sid's `rustc`/`cargo` instead of
  Ubuntu's `rust-1.91`, `bpftool` instead of `linux-tools-*`, `--jobs nproc`,
  and a per-tag generated install manifest (version bumps require no
  packaging edits).
- `scx_loader`, `scxctl` and `scxtui` used to live in the main scx tree and
  were moved to their own repository; they are packaged here from
  [sched-ext/scx-loader](https://github.com/sched-ext/scx-loader).

## References

- [sched-ext/scx](https://github.com/sched-ext/scx) — schedulers and tools
- [sched-ext/scx-loader](https://github.com/sched-ext/scx-loader) — loader daemon, scxctl, scxtui
- [sched-ext/scx-scheds-packaging-deb](https://github.com/sched-ext/scx-scheds-packaging-deb) — upstream Debian/Ubuntu packaging this repo started from
- [sched_ext wiki](https://github.com/sched-ext/scx/wiki)
- [CachyOS sched_ext guide](https://wiki.cachyos.org/configuration/sched-ext/)
