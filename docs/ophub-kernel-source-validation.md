# ophub-kernel 6.18.54 validation

Validated on 2026-09-26 with native aarch64 Gentoo, GCC 16.2.0 and DKMS 3.4.3.
The full default configuration was built, not a tiny substitute kernel.

## Build and staged installation

The actual ebuild completed unpack, prepare, configure, compile, test and install
with `USE="test -debug"`, `FEATURES=test` and `MAKEOPTS="-j4"`. Installation here
means Portage's staged image; the new kernel was not merged into either machine
and neither machine was rebooted into it.

- Kernel release: `6.18.54-ophub-gentoo-r0`.
- Image: 36067840 bytes, SHA256
  `407e90c6e1fb3c3d85d7acf36f9506e8252480e1b112bed2982a73b4e06d9472`.
- 3150 modules and 588 DTBs installed, including `rockchip/rk3399-tpm312.dtb`.
- TPM312 DTB SHA256:
  `5aa45a49cd88c0e6cf9c1f0dc4c2ddf2a43301914391570fbf9bd25724ca9537`.
- The staged tree has no `/boot`; the build symlink targets the new release's
  `/usr/src/linux-*` tree. Saved config and artifact config match exactly.
- Exported headers contain .config, Module.symvers, generated headers and Kbuild
  executables. `make kernelrelease` returns the expected release.
- Panfrost, btusb and rtw88_core module vermagic matches the expected release.
- `depmod -b STAGED_ROOT 6.18.54-ophub-gentoo-r0` succeeded without warnings;
  modules.dep contains all 3150 modules.
- Measured build directory: 3573232 KiB; staged image: 314752 KiB, excluding
  downloaded archives and separate test directories.

A separate actual configure run with `USE="savedconfig debug"` restored a custom
hostname and enabled DWARF5/BTF, while retaining the fixed release suffix.
The debug configuration was not subjected to a second full kernel build.

## External modules

The ebuild's src_test exported a fresh header tree and built its test module,
checking kernelrelease and vermagic against the real built kernel.

Separately, real DKMS add/build compiled the locally used tcp-brutal 1.0.3 source
against the installed-image headers using private source/state/install roots.
Its vermagic is:

```text
6.18.54-ophub-gentoo-r0 SMP preempt mod_unload aarch64
```

No test module was installed or loaded; the private DKMS registration was removed.
The existing host and TPM312 DKMS installations were not altered.

## Packaging and dependencies

- pkgcheck passes for the source package and virtual, both with the ARM64 23.0
  profile and without restricting the profile scan.
- Shell syntax, metadata XML and git whitespace checks pass; both distfiles and
  all package files are covered by Manifest checksums.
- Source-only emerge pretend passes on the build host.
- TPM312 emerge pretend for source kernel + gentoo-cs virtual + DKMS passes.
  The temporary overlay was supplied only through the process environment.
- TPM312 emerge pretend updating only the virtual schedules just its r10 to r11
  upgrade. It retains the installed binary provider instead of forcing a source
  kernel build.

These are build/package checks, not a TPM312 boot or hardware regression test.
Bootloader deployment and initramfs generation remain a separate operation.
