# ophub-kernel-bin (ARM64)

This package puts an audited ophub kernel, its in-tree modules, DTBs and matching
prepared module build tree under Portage ownership. It is intended initially for
an RK3399 TPM312 already running the **2026-09-22 build of 6.18.53-ophub**.
It does not install a bootloader, change `/boot`, regenerate initramfs, reboot,
select `/usr/src/linux`, or enable automatic DKMS installation.

## Obtain the exact distfile

Upstream replaces `kernel_stable/6.18.53.tar.gz` with different builds that retain
`uname -r = 6.18.53-ophub`. This ebuild intentionally uses `RESTRICT=fetch` and a
Manifest for the original archived build. It is **not** a working download link
for the current upstream asset. Do not substitute today's download or regenerate
the Manifest to silence a checksum failure.

Use your archived original `6.18.53.tar.gz`, **122846477 bytes**, whose SHA256 is:

```text
269dd8ded019f829723968a236bac40335dc9488aac8f22cf1afd5b9f3a20bb7
```

The original GitHub asset was `580626792`, created `2026-09-22T05:20:47Z`.
Hashes of every inner archive are recorded in `provenance.json`. If you do not
have that exact archive, this version cannot currently be installed; a newer
build needs a separately audited ebuild and Manifest. The archive is not stored
in this Git repository.

As root on the target machine, after checking the above checksum:

```sh
install -m 0644 /path/to/archived/6.18.53.tar.gz \
  "$(portageq envvar DISTDIR)/ophub-kernel-6.18.53_p20260922-arm64.tar.gz"
mkdir -p /etc/portage/package.accept_keywords
printf '%s\n' 'sys-kernel/ophub-kernel-bin ~arm64' \
  'virtual/linux-sources::gentoo-cs ~arm64' \
  > /etc/portage/package.accept_keywords/ophub-kernel
emerge --ask sys-kernel/ophub-kernel-bin:6.18.53
```

Enable the `gentoo-cs` repository first using its normal repository configuration.
Selecting `:6.18.53` keeps this rollback slot in world when future slots arrive.
Existing in-tree module files must match byte-for-byte; otherwise installation
aborts before merging. Do not bypass that check to replace a same-release ABI.

## Installed paths and module builds

- `/usr/src/linux-6.18.53-ophub/`: `.config`, `Module.symvers`, generated headers,
  Makefiles and the upstream ARM64 host tools.
- `/lib/modules/6.18.53-ophub/build`: points to that prepared tree.
- `/lib/modules/6.18.53-ophub/kernel/`: upstream in-tree modules.
- `/usr/lib/ophub-kernel/6.18.53-ophub/`: Image, config, System.map, and
  `dtbs/{rockchip,amlogic,allwinner}/`.

This is not a complete source tree: it cannot rebuild the kernel, run arbitrary
Kconfig changes, or promise every third-party module's private source needs.
`sys-kernel/linux-headers` supplies userspace UAPI headers and is a separate
package. Do not replace it with this tree. There is intentionally no `source`
symlink claiming to provide complete sources.

The upstream build used ARM GCC 15.3.1; normal Kbuild module builds were also
verified with Gentoo GCC 15.3.0. Keep a compatible toolchain available. Upstream
prepared host tools are ARM64/glibc binaries; this is not a cross-build SDK.

```sh
kver=$(uname -r)
readlink -f "/lib/modules/$kver/build"
make -s -C "/lib/modules/$kver/build" kernelrelease
make -C "/lib/modules/$kver/build" M="$PWD" modules
```

For Gentoo module ebuilds using `linux-mod-r1`, specify the desired kernel as
needed with `KERNEL_DIR=/usr/src/linux-6.18.53-ophub`. This package is not a Gentoo
Distribution Kernel provider and does not promise `dist-kernel` rebuild hooks.

## DKMS

The companion ARM64 `virtual/linux-sources-3-r10` adds this prepared tree as an
alternative provider, retaining Gentoo's existing providers. It prevents the
DKMS dependency from pulling an unrelated complete kernel after this package
has been installed. Revisit this override when upstream changes the virtual.

```sh
emerge --ask virtual/linux-sources::gentoo-cs sys-kernel/dkms
# For an already registered module:
dkms build -m MODULE -v VERSION -k 6.18.53-ophub
# Install it only when you intend to use that driver:
dkms install -m MODULE -v VERSION -k 6.18.53-ophub
```

No private module-signing key is distributed. BTF generation may be skipped
because the archive does not include vmlinux. A smoke build is not proof that an
arbitrary driver is compatible with this kernel or that its hardware works.

## Boot files and upgrades

An existing TPM312 installation can keep its currently validated `/boot/Image`,
`/boot/uInitrd`, DTB and extlinux configuration. Matching modules and headers can
be imported without switching the running kernel.

For a future, separately versioned kernel, prepare a new `/boot/kernels/KVER/`
directory. Copy this package's Image and the board's DTB there, generate a Gentoo
initramfs with dracut for that KVER, and use `mkimage` from
`dev-embedded/u-boot-tools` if the board expects a U-Boot uInitrd. Verify the
required root-filesystem/eMMC drivers and establish a tested recovery path
before changing the boot entry. The upstream initrd is deliberately not installed.
No automated boot switch or rollback is provided by this ebuild.

Do not unmerge a running or rollback kernel slot. Keep each retained slot
selected in world. A Btrfs root snapshot does not include a separate `/boot`.

To maintain this package: archive and hash a coherent upstream release, assign
a new dated `_pYYYYMMDD` version, update `KV_FULL` as needed and the provenance,
verify module/header compatibility, and test on the target architecture. Builds
with the same KVER share one SLOT and cannot coexist under `/lib/modules/KVER`;
never replace one while depending on a different same-name boot image.
