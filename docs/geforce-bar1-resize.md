# GeForce BAR1 调整

`sys-apps/geforce-bar1-resize` 固定上游提交
`53466608917ff5d8c660eefcee7c7e6c4261ef1b`。通过 Linux PCI sysfs 和 NVIDIA
配置空间的易失性覆盖，在 NVIDIA 驱动绑定前增大 BAR1；不写主板 BIOS 或显卡 VBIOS。

ebuild 使用 patch 将上游 systemd 服务的 `/usr/local/sbin` 路径改为 `/usr/sbin`。
服务不自动启用，也不安装用于 PCIe switch 的实验性布局内核模块。

## 安装与预检

```sh
emerge --ask sys-apps/geforce-bar1-resize
geforce-bar1-resize check --vram 32G 0000:41:00.0
```

`systemd` USE 安装启动服务和 udev 记录规则；`verify` USE 安装诊断源码与脚本。
验证工具需要已有的 NVIDIA 驱动及用户态库；该包不会替换驱动。

上游目前主要验证了 RTX 3080 20GB。其他卡即使通过结构检查，也应先在空闲机器上
测试并验证真实映射，不能只看 `nvidia-smi` 的数字。Above 4G Decoding、足够的
64 位 PCI 地址空间和 `resource1_resize` 接口是前提；驱动应从根文件系统加载。

## 限定一张卡的开机配置

确认 PCI 地址和设备 ID 后创建 `/etc/geforce-bar1-resize.conf`。以下是
RTX 4080 SUPER 32GB 改卡的示例，其他硬件应替换地址和 ID：

```bash
CARDS="0000:41:00.0"
SIZE=32G
ROUTE=auto
LAYOUT=off
DRIVER_OPTION=auto
CONSOLE=skip
declare -A CARD=(
    [0000:41:00.0]="ids=10de:2702/10de:8986 size=32G route=0x610 driver_option=auto"
)
```

在驱动已正常加载时记录显存、检查计划，再启用服务：

```sh
geforce-bar1-resize record
geforce-bar1-resize check --report 0000:41:00.0
geforce-bar1-resize plan
systemctl enable geforce-bar1-resize.service
reboot
```

该路线生成按设备限定的 `RMForceStaticBar1=0` 配置。它与依赖静态 BAR1 映射的
P2P 补丁不是同一条路径；增大 BAR1 不代表已经启用 CUDA P2P。

## 验证

```sh
journalctl -b -u geforce-bar1-resize --no-pager
lspci -vv -s 0000:41:00.0
nvidia-smi -q -d MEMORY
python3 /usr/share/geforce-bar1-resize/verify/vk_heaps.py \
    --bdf 0000:41:00.0 --expect-bar1 32G
```

应同时确认 PCI Region 1 实际为 32 GiB、驱动 BAR1 为 32768 MiB，以及
`DEVICE_LOCAL|HOST_VISIBLE` 内存堆覆盖可用显存。

本次本地测试的一张 `10de:2702 / 10de:8986` RTX 4080 SUPER 32GB 改卡，在
Linux 6.18.63、NVIDIA 620.70.06 下，`0x610` 从 `00001001` 变为 `00001c81`，
BAR1 能力从 `0007fc00` 变为 `000ffc00`，Linux 实际分配了 32 GiB。
30 GiB 的 CPU 写/GPU 读、GPU 写/CPU 读及最终别名检查通过，错误数和新增 Xid/AER 均为 0。
CUDA/OpenCL 计算、30 GiB GPU 显存读写、Vulkan 提交、OpenGL 4.6 离屏渲染也通过。
启用打包的 systemd 服务后再次重启，PCI Region 1 和驱动 BAR1 均自动恢复为 32 GiB，
GPU 功能复测通过；尚未验证断电冷启动。
这是一张卡的结果，不代表所有 AD103 或改卡都已验证。

## 回退

调整是易失性的。要停止每次启动重新应用，可禁用启动服务、屏蔽 udev 记录模板，
移走生成的驱动选项并重启：

```sh
systemctl disable --now geforce-bar1-resize.service
systemctl mask geforce-bar1-resize-record@.service
mv /etc/modprobe.d/zz-geforce-bar1-resize.conf \
    /etc/modprobe.d/zz-geforce-bar1-resize.conf.disabled
reboot
```

若原先保留 `options nvidia NVreg_EnableResizableBar=1`，重启后由原驱动选择原生
支持的 BAR1 上限；本次测试卡为 16 GiB。再次启用本包前应取消记录模板的 mask。
