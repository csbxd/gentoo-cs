# ophub-kernel: ARM64 source builds

`sys-kernel/ophub-kernel` compiles Image, modules and DTBs from the ophub Linux
source tree. It uses immutable source and configuration commits with Manifest
checksums, rather than a moving branch or a published binary kernel archive.

The initial version is 6.18.54:

- Sources: https://github.com/ophub/linux-6.18.y/commit/4e68e1932480960f2f4a95e80e424b34d0737dfb
- Stable configuration: https://github.com/ophub/kernel/blob/35527918391e697f994d9efa02948d4308a7a766/kernel-config/release/stable/config-6.18
- Kernel release: `6.18.54-ophub-gentoo-r0`.
- Architecture: native ARM64 builds. Cross-compilation is not yet supported.

This is a local build of ophub sources, not a byte-identical reproduction of
ophub's published binaries. It has its own release suffix, including the ebuild
revision, and can coexist with `ophub-kernel-bin`. Never reuse the vendor binary
kernel's module directory for locally compiled modules.

## Install and configure

```sh
emerge --ask sys-kernel/ophub-kernel:6.18.54
emerge --ask virtual/linux-sources::gentoo-cs sys-kernel/dkms
```

Keep the repository qualifier on the virtual package when another overlay
provides a higher version without this provider. Keep every kernel slot needed
for boot or recovery selected in world.

`USE=savedconfig` restores a custom kernel config using Gentoo's savedconfig
mechanism. Every install saves the effective config in
`/etc/portage/savedconfig/sys-kernel/ophub-kernel-6.18.54`. A config can be provided
before the first build at that path or at the version-independent
`/etc/portage/savedconfig/sys-kernel/ophub-kernel` path. Version-specific saved
configs take precedence over the version-independent file.

The package always overrides the release suffix, disables automatic Git suffixes,
compiler warnings as errors, GCC plugins, module signing/compression and external
certificate paths. `CONFIG_MODULES=y` is required. `USE=debug` controls DWARF5 and
BTF; they are disabled by default to reduce build space and memory. Configs and
user patches must remain compatible with these settings. `USE=test FEATURES=test`
builds an external module against the exported headers and checks its release.

The upstream config covers many ARM64 boards, so a full build is substantial.
The tested default build used about 3.4 GiB for the work tree and 307 MiB for
the install image, plus distfiles and temporary tests. Reserve at least 6 GiB
of free build space; debug or custom configs can need substantially more.
TPM312's currently free eMMC space may be insufficient. Start with `MAKEOPTS="-j2"` on a 4 GB board and check
space before building. Reducing jobs does not reduce the disk space required.

## Installed artifacts

- `/usr/lib/ophub-kernel/6.18.54-ophub-gentoo-r0/Image`
- `/usr/lib/ophub-kernel/6.18.54-ophub-gentoo-r0/{config,System.map,dtbs/}`
- `/lib/modules/6.18.54-ophub-gentoo-r0/`
- `/usr/src/linux-6.18.54-ophub-gentoo-r0/`
- `/lib/modules/6.18.54-ophub-gentoo-r0/build` points to that build tree.

The build tree is exported by the kernel's `install-extmod-build` helper and
contains generated headers, Module.symvers, Kbuild tools and the exact config.
It is a prepared external-module tree, not the entire source checkout. To retain
full sources for development, use Portage's `FEATURES=noclean` work directory.
`sys-kernel/linux-headers` only supplies userspace UAPI and is unrelated.

```sh
make -s -C /lib/modules/6.18.54-ophub-gentoo-r0/build kernelrelease
dkms autoinstall -k 6.18.54-ophub-gentoo-r0
modinfo -k 6.18.54-ophub-gentoo-r0 brutal
```

Existing modules built for `6.18.53-ophub` must be rebuilt for this kernel.

## Boot deployment

Installation runs depmod but does not change /boot, U-Boot, extlinux or initramfs,
or select `/usr/src/linux`. This package is not a Gentoo Distribution Kernel and
does not trigger installkernel or automatic module-rebuild hooks.

For TPM312, prepare a separate versioned boot directory with Image and
`dtbs/rockchip/rk3399-tpm312.dtb`, generate a matching initramfs for the installed
kernel, and apply the board's required U-Boot wrapper. Verify a recovery procedure
before changing the boot entry. Preserve the current working kernel and its
modules. A root Btrfs snapshot does not include a separate /boot partition.

Rebuilding the same ebuild with a different config still uses the same release:
plan a reboot and rebuild external modules; modules already in memory do not
change when their files are replaced. For parallel custom configurations, use a
separate ebuild revision. Do not unmerge a running or recovery kernel.
