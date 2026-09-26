# ophub-kernel-bin validation — 2026-09-26

Tested on an RK3399 TPM312 running Gentoo ARM64/glibc and the original
2026-09-22 `6.18.53-ophub` kernel. No reboot or kernel switch was performed.

- Verified the outer archive against its original GitHub asset digest and the
  ebuild Manifest; all six inner archive SHA256 checks passed.
- Installed and reinstalled `ophub-kernel-bin-6.18.53_p20260922:6.18.53` with
  `USE=test FEATURES=test` through Portage. The final ebuild's kernelrelease
  assertion and external Kbuild module test both passed with Gentoo GCC 15.3.0.
- `/lib/modules/6.18.53-ophub/build` resolves to
  `/usr/src/linux-6.18.53-ophub`. Its config, symbol versions, localversion file,
  Image and build symlink are recorded in the package database.
- Installed `virtual/linux-sources-3-r10::gentoo-cs` and official Gentoo
  `dkms-3.4.3`; the resolver needed only these two packages, no unrelated kernel
  sources. Explicitly selected the repo-qualified virtual because another
  enabled overlay offers a higher revision without the ophub provider.
- Ran a real `dkms add` / `dkms build` in isolated DKMS state/source directories.
  Built vermagic: `6.18.53-ophub SMP preempt mod_unload aarch64`, matching an
  installed in-tree module. Removed the temporary registration and source;
  no test module was installed or loaded. Default `dkms status` remains empty
  and dkms.service is disabled.
- SHA256 hashes of the existing boot Image, uInitrd, board DTB and extlinux
  configuration remained unchanged. Kernel stayed `6.18.53-ophub`.
- Existing world entries remained selected; added the kernel slot, DKMS, and the
  repo-qualified virtual. Wired SSH remained available, gateway Ping 3/3,
  failed systemd units zero, and all Btrfs device error counters zero.
- `bash tests/ophub-kernel-preinst.sh` passed: first installation and identical
  module adoption are allowed, a different existing same-release module aborts.
- `pkgcheck scan --repo . --profiles default/linux/arm64/23.0
  sys-kernel/ophub-kernel-bin virtual/linux-sources` passed with no findings.
  An unrestricted profile scan reports the explicitly unsupported musl profiles:
  upstream's prepared host binaries require glibc, enforced by REQUIRED_USE.

Expected build notices: the upstream kernel used GCC 15.3.1 while this target
used 15.3.0; BTF generation was skipped because the archive lacks vmlinux.
The kernel has module signing disabled, so DKMS correctly built an unsigned
module. These results do not validate arbitrary third-party drivers, full kernel
source builds, or automatic bootloader/initramfs integration.

Install/archive requirements and maintenance limitations are documented in
[the package README](../sys-kernel/ophub-kernel-bin/files/README.md).
