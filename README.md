# Armbian Mobile Devices

This repository will integrate mobile ARM devices with the Armbian Build Framework.
The first reference device is Xiaomi Mi 8 (`xiaomi-dipper`, Qualcomm SDM845).

The repository contains a pinned Armbian Build Framework snapshot plus the initial
SDM845 family and `xiaomi-dipper.wip` board integration. The board remains WIP until
the kernel compiles and a real Xiaomi Mi 8 passes hardware validation.

## Repository rules

- Trunk branch: `main`.
- Device names use upstream-style names such as `xiaomi-dipper`.
- Proprietary firmware, calibration data, identifiers, and generated build output
  must not be committed.
- The first-stage product line is Linux 6.12.y LTS on SDM845. Each release pins an
  exact, tested 6.12.N revision; the historical 6.12.91 reference is used only for
  reproduction, while security updates track the latest validated 6.12.y point.

## Build environment

When run as a regular user with access to the Docker daemon, the Armbian framework
automatically delegates a normal build to Docker. From this repository, use:

```bash
./compile.sh \
  BOARD=xiaomi-dipper \
  BRANCH=current \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no
```

Docker isolates the build toolchain and package installation from the host. The
framework still needs access to the repository, its build cache and output mounts,
and uses a privileged container for loop devices and image creation. Flashing a
phone is a separate, host-side step and is not performed by this command. A root
shell runs natively only after the framework's safety prompt is explicitly
accepted; for a non-interactive root run, set `ALLOW_ROOT=yes`. Use a regular user
in the `docker` group when container isolation is required. Do not pass `docker` as
a second build command.

## Upstream provenance

The framework files are imported from `armbian/build` commit
`2a53f15877bb694663ba04035a848cea08535d2f`; this repository is currently an
independent local Git repository, not a configured GitHub fork. The pinned source,
patch and reference revisions are recorded in [docs/upstream-audit.md](docs/upstream-audit.md).

See [EXECUTION_PLAN.md](EXECUTION_PLAN.md) for the staged implementation and
acceptance gates.
