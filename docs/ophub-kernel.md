# Gentoo 上的 ophub 内核

| 包 | 来源 | 用途 |
| --- | --- | --- |
| `sys-kernel/ophub-kernel` | 固定提交的 ophub 源码及 stable 配置，本机编译 | 自定义内核配置、通过 Portage 构建新内核 |
| `sys-kernel/ophub-kernel-bin` | 固定校验的已存档二进制包 | 管理已经验证过的 ophub 发布构建及匹配 headers |

两者均安装模块、DTB、Image 和配套的外部模块构建树，均不自动修改启动配置。
源码包的 kernel release 带 `-ophub-gentoo-rN`，与二进制发布的 `-ophub` 分开。
同一内核基础版本的两个包可以同时安装，但外部模块必须分别编译。

## 安装源码版

本版提供 `6.18.54`，仅支持原生 ARM64 构建：

```sh
emaint sync -r gentoo-cs
emerge --ask sys-kernel/ophub-kernel:6.18.54
emerge --ask virtual/linux-sources::gentoo-cs sys-kernel/dkms
```

请检查 emerge 计划。构建会使用上游覆盖多种设备的配置；4 GB 内存设备建议
`MAKEOPTS="-j2"`，并预留足够编译空间。TPM312 当前剩余 eMMC 空间不代表足以
编译整个内核，不能仅凭源代码压缩包大小估算。本次默认构建的工作树约 3.4 GiB、
安装暂存目录约 307 MiB，另需归档及临时文件空间，建议至少预留 6 GiB。默认关闭
DWARF/BTF 调试信息；开启调试信息或自定义配置会改变空间需求。

自定义配置时，在 `/etc/portage/package.use/ophub-kernel` 中加入：

```text
sys-kernel/ophub-kernel savedconfig
```

将完整 `.config` 放到 `/etc/portage/savedconfig/sys-kernel/ophub-kernel`。
每次安装也会保存生效配置到带版本的 savedconfig 文件中；带版本的文件优先。
构建执行 `olddefconfig` 处理新增选项。包固定覆盖版本后缀、签名/压缩和若干构建
选项，具体见[包内说明](../sys-kernel/ophub-kernel/files/README.md)。需要 DWARF5/BTF
时启用 `debug`；这会增加构建空间和依赖。

## Headers 和 DKMS

```sh
KVER=6.18.54-ophub-gentoo-r0
readlink -f /lib/modules/${KVER}/build
make -s -C /lib/modules/${KVER}/build kernelrelease
dkms autoinstall -k ${KVER}
modinfo -k ${KVER} brutal
```

`build` 指向 `/usr/src/linux-${KVER}`，包含本次编译的 `.config`、generated headers、
`Module.symvers` 及 Kbuild 工具。该目录用于构建外部模块，不是可重新配置整个内核的
完整源码目录；完整源码可通过 `FEATURES=noclean` 保留在 Portage 工作目录中。

`sys-kernel/linux-headers` 只提供用户空间 UAPI，不能替代上述构建树。
请保持 `virtual/linux-sources::gentoo-cs` 的仓库限定，避免其他 overlay 的虚拟包
再次拉入无关的内核源码。

## 启动切换单独处理

Image、config、System.map 和 DTB 位于 `/usr/lib/ophub-kernel/${KVER}/`。
安装完成不等于正在运行该内核：本包只运行 depmod，不调用 installkernel、dracut、
U-Boot 或修改 extlinux，也不自动重启。

TPM312 应将新 Image 与 `dtbs/rockchip/rk3399-tpm312.dtb` 准备到独立启动目录，
生成匹配新内核的 initramfs 并按现有引导方式包装。先验证恢复方式，再切换启动项。
保留旧内核及其模块；Btrfs 根快照不包含独立的 `/boot`。

本次源码构建验证不等于新内核已在 TPM312 启动并完成硬件回归测试。

## 后续版本维护

每次版本更新都要固定源码和配置的完整 commit SHA，核对源树 Makefile 的内核版本，
更新 SRC_URI 与 Manifest，并重新进行完整构建及外部模块测试。不能将浮动 `main`
或今天下载的同名发布包作为旧版本的替代品。

修订相同版本的打包方式时增加 ebuild revision；revision 会进入 kernel release。
修改 savedconfig 后重装同一 ebuild 仍会使用相同 release，需要重新构建外部模块并
安排重启。若需要让不同自定义配置并存，应使用不同的 ebuild revision。
