# Electron 1.8.6 / Linux ARM64 / 16 KiB pages

参考 [csbxd/electron11-16k](https://github.com/csbxd/electron11-16k)，为
Electron 1.8.6、Chromium 59.0.3071.115 和 V8 5.9.211.38 准备的原生 ARM64 构建。

适配包含两部分：

- 生成快照时使用 `v8_os_page_size="16"`，并保留 Intl/ICU 和
  `v8_promise_internal_field_count=1`，使快照布局与 Electron 的 V8 一致。
- 将 Chromium 和 PDFium 的 PartitionAlloc 系统/分配粒度设为 16 KiB，
  分区页设为 64 KiB。所有使用这些头文件的模块都需要重新编译。

`full/compat-patches/` 和 Electron/Breakpad 补丁处理旧源码在原生 ARM64、
GCC 7、glibc 2.27 构建环境中的兼容问题。编译过程中没有使用已失效的
libchromiumcontent S3 二进制服务。

## 构建

在原生 Linux ARM64 主机上准备 Git、Podman、Node/npm 和 Python 3.12 或更新版本。
源码下载和校验在主机执行；编译使用 Ubuntu 18.04 容器内的 Python 2.7/GCC 7。

```sh
bash full/build-all.sh
```

源码版本、子模块提交和 Chromium 压缩包 SHA-256 记录在
`full/source-lock.json`。额外缺失的 FreeType 源码由
`full/source-deps.json` 锁定并校验。npm 构建依赖使用锁文件安装。

完整 Electron 运行时输出到 `full/electron186-runtime/`。构建是增量的；
中断后重新执行命令会复用已完成的对象文件。

## 与已安装的迅雷组合

保留迅雷的应用文件、原生模块和下载 SDK，使用新编译的 Electron：

```sh
python3 full/make-thunder-runtime.py \
  full/electron186-runtime ./thunder16k \
  --installed-thunder /opt/xunlei-download
python3 full/verify-runtime.py ./thunder16k --json ./elf-layout.json
./thunder16k/run-thunder.sh
```

目标目录需要尚不存在。运行时文件和资源会复制到独立目录，不依赖构建容器里的
绝对路径。

## 验证材料

`pa59/` 包含独立分配器测试及其源码锁定信息；`snapshot/` 包含最小 V8/ICU
生成器构建脚本；`tests/` 包含 Xvfb/CDP 页面观测、原生模块和本地 HTTP 下载测试。
完整集成结果以随交付提供的测试记录为准。

此适配目标是 16 KiB ARM64 Linux。分配粒度也满足 4 KiB 内核的对齐要求，
但本次实际运行验证仅针对 16 KiB；64 KiB 内核不在本次适配范围内。

Electron、Chromium、V8、PDFium 及下载时取得的其他依赖继续适用各自的上游许可。
补丁保留其源文件和上游变更的来源；构建脚本的许可见本目录 LICENSE。
