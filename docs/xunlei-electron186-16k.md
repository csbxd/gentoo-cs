# 迅雷 / Electron 1.8.6 的 ARM64 16 KiB 适配

`net-misc/xunlei-download-1.0.0.5-r2` 保留原厂迅雷应用、原生模块和下载 SDK，
替换为重新编译的 Electron 1.8.6 运行时。原厂 deb 仍从 Kylin 下载；本仓库的
Release 只分发开源 Electron 运行时。

参考项目：[csbxd/electron11-16k](https://github.com/csbxd/electron11-16k)。
构建源码、版本锁定和补丁位于 [`scripts/electron186-16k`](../scripts/electron186-16k)。

## 修复

- 用 `v8_os_page_size="16"` 重新生成 V8 快照，保持 Intl/ICU 和 Promise 内部字段
  配置与运行时一致。原快照代码块超过 16 KiB 系统下的代码页可用空间，会在
  JavaScript 初始化时崩溃。
- 重编 Chromium 和 PDFium 的 PartitionAlloc 及全部使用方：系统粒度改为
  16 KiB，分区页改为 64 KiB。原渲染器在 `SetSystemPagesInaccessible` 崩溃。
- 修复原生 ARM64 构建工具选择、旧源码的标准 C++ 声明、glibc/ucontext 和
  DMA-BUF UAPI 兼容性。
- GCC 构建关闭会触发内部编译器错误的 LTO。主程序隐藏私有 `hb_*` 符号，
  防止旧内置 HarfBuzz 抢占现代系统 Pango/HarfBuzz。
- 启动器创建客户端首次启动需要的 BHO 配置父目录；不强制禁用 GPU 或沙箱。

## 验证

2026-10-18 在 Gentoo / Asahi Linux ARM64、16,384 字节内存页上完成：

| 检查 | 结果 |
| --- | --- |
| Chromium、PDFium allocator debug/release | 原版失败，修复版通过 |
| 完整 Electron 源码构建 | 通过 |
| 8 个运行时/迅雷 ELF 的 16 KiB 加载布局 | 通过 |
| 真实 renderer 执行 DOM JavaScript / 绘制 | 返回 42，截图正常 |
| 迅雷主界面、登录窗口、新建任务面板 | 正常显示 |
| Xvfb 持续运行 120 秒 | 4 个页面，0 renderer 崩溃、0 JS 异常 |
| 真实桌面默认参数启动 | 正常，未传入禁用 GPU/沙箱参数 |
| 下载 SDK 本地 HTTP 128 KiB 下载 | 完成状态、错误码 0、SHA-256 一致 |
| 真实界面菜单“退出” | 主进程退出码 0，子进程退出 |

结构化结果见 [`xunlei-electron186-16k-results.json`](xunlei-electron186-16k-results.json)。
账号登录、会员及账号服务功能未作验收。桌面测试观察到一次非致命的
`Pipe ECONNRESET`，未影响上述界面、传输和菜单退出检查。旧客户端对 SIGINT
使用关闭到托盘的路径，因此退出验收采用实际“退出”菜单。

## 安装与重建

```sh
emerge --ask =net-misc/xunlei-download-1.0.0.5-r2::gentoo-cs
```

需要自行构建运行时时，在原生 ARM64 主机准备 Podman、Git、Node/npm 和
Python 3.12 或更新版本：

```sh
bash scripts/electron186-16k/full/build-all.sh
```

编译使用 Ubuntu 18.04 容器中的 GCC 7/Python 2.7，源码按提交和 SHA-256 锁定。
构建日志、版本锁定和运行时内的 `BUILDINFO.json` / `SOURCE-LOCK.json` 可用于核对。

本机已通过 Portage 从 `1.0.0.5-r1::benzene-overlay` 升级到此版本，依赖解析仅升级
迅雷一项。安装后的系统启动器、Node/原生模块、本地下载、16 KiB ELF 布局和
退出菜单再次验证通过。原厂两处遗留 RPATH 已清理，代码段和加载段布局未改变。
