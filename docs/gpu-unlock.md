# gpu-unlock on Gentoo

`sys-kernel/gpu-unlock-2.0.0_p20261028` packages
[Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) at
`7eb51bccae0a0b7e599e084d971170e9a1e82d0c` using `linux-mod-r1`.
It builds the kernel module locally and generates its firmware assets from
the pinned, checksum-verified NVIDIA 610.43.03 inputs. The NVIDIA installer
is read as an archive, not executed. The installed NVIDIA driver is separate.
No generated NVIDIA firmware or binary package is published here.

## Installation and activation

```text
# /etc/portage/package.accept_keywords/gpu-unlock
sys-kernel/gpu-unlock ~amd64

# /etc/portage/package.use/gpu-unlock
sys-kernel/gpu-unlock dist-kernel initramfs bench
```

```sh
emerge -av sys-kernel/gpu-unlock
modinfo gpu_unlock
```

`initramfs` installs dracut configuration that loads `gpu_unlock` early.
With `dist-kernel`, the eclass rebuilds the installed kernel's initramfs.
Firmware dependencies are declared by the module and included by dracut.
Verify the resulting image before rebooting.

The module does nothing until the kernel command line selects a card:

```text
gpu_unlock.targets=0000:41:00.0
```

Use the host's actual full PCI address, obtained with `lspci -D`. Ada support
is experimental upstream. Retain a stock boot entry and initramfs before
activating it. Test a one-shot entry first. After a successful test, add the
parameter to the applicable bootloader configuration and `/etc/kernel/cmdline`
when used by the host's kernel installation tools. Regenerate GRUB as needed.

```sh
journalctl -k -b | grep gpu_unlock
nvidia-smi
```

Successful tested readbacks were `SS0=0x88888888`, `SS1=0x8`, followed by a
clean FLR/handoff and `gpu_unlock: unlocked`. A module merely being loaded
does not prove it unlocked the card. NVIDIA must bind after this transaction.

On the tested server, `geforce-bar1-resize` runs later from the root filesystem,
before NVIDIA loads. It reapplies the independent 32 GiB BAR1 override after
the unlock's FLR. Confirm both the unlock and the actual BAR1 size after boot.

To roll back, select the saved stock-initramfs entry without the opt-in
parameter. Remove the parameter from persistent boot configuration as well.
The selectors are volatile; a complete power-off clears their hardware state.
Rebuild initramfs images after removing the package if removing its embedded
module and firmware too. The stock image retained for this test is
`initramfs-6.18.63-s8030-r2-stock.img`, with GRUB ID `gpu-unlock-stock`.

## Packaged comparison tools

`USE=bench` compiles a standalone CUDA/cuBLAS benchmark. Its build defaults
to SM 89 for the tested Ada card. Set `GPU_UNLOCK_BENCH_ARCH` through
`package.env` before building it for another architecture. The module itself
is not tied to the benchmark's architecture.

Run with exclusive use of the NVIDIA GPU and stop model servers first:

```sh
sudo python3 /usr/share/gpu-unlock/bench/run-matrix.py --out /var/tmp/gpu-before
# Activate the unlock and reboot, then run the same installed binary:
sudo python3 /usr/share/gpu-unlock/bench/run-matrix.py --out /var/tmp/gpu-after
```

The suite measures 4096 and 8192 square GEMMs with FP16/BF16/TF32 inputs and
FP32 accumulation. FP16 accumulation and strict FP32 are controls. It uses
one second of warm-up per case and seven timed batches of about 400 ms,
reporting the median. Rates count `2*N^3` operations. Fixed inputs are exactly
representable in all tested input formats. Every output is checked for
finiteness; 64 locations are checked against a CPU reference, and a digest
of the full output is recorded for before/after comparison.

Both stock boost and a fixed 1800 MHz GPU clock are measured. Root privileges
are needed to set clocks. The runner resets GPU clock locking in `finally`.
Sensor CSV files and summaries cover the complete pass, including warm-up,
verification and allocation gaps. Their average power is not a per-GEMM power
measurement. The card's 320 W power limit is kept unchanged.

For Strata, start a fresh instance with the same model and private run config
in each phase, and use the same existing credential file:

```sh
python3 /usr/share/gpu-unlock/bench/strata-compare.py \
  --out /var/tmp/strata-before --key-file /path/to/private-api-key
```

Repeat after unlock with a new output directory. The tool performs a short
warm-up, then three 427-token and three 12332-token prompts on the tested
IQ3_XXS tokenizer, each requesting 256 output tokens. Inputs, seed, temperature,
thinking setting and request order are fixed. It records request hashes,
actual prompt/cache counts, engine timings and response hashes without
logging the credential. The two groups use distinct leading text so prefix
reuse cannot replace the prompt-processing work. Model routing, adaptive
expert placement and host memory effects still introduce application variance.

## Measured host

The 2026-11-16 comparison used an EPYC 7302P, 31.2 GiB of host RAM, an AD103
RTX 4080 SUPER modified to 32 GiB (`10de:2702`), kernel 6.18.63-s8030-r2,
NVIDIA 620.70.06 and CUDA Toolkit 13.4.1. BAR1 stayed at 32768 MiB. The
benchmark executable's hash was identical across the reboot.

Raw sanitized measurements and the final comparison are in
`benchmarks/gpu-unlock-rtx4080s-32g-20261116.json`. These are short hardware
and application tests, not a long-duration stability qualification.

8192-square GEMMs, stock boost, median of seven timed batches:

| Mode | Before TFLOPS | After TFLOPS | Change |
| --- | ---: | ---: | ---: |
| FP16 input, FP32 accumulation | 107.68 | 192.18 | +78.5% |
| BF16 input, FP32 accumulation | 107.65 | 189.78 | +76.3% |
| TF32 input, FP32 accumulation | 55.04 | 101.60 | +84.6% |
| FP16 accumulation control | 190.64 | 189.37 | -0.7% |
| Strict FP32 control | 39.40 | 39.15 | -0.6% |

At a verified fixed 1800 MHz, FP16/BF16 gained 92.2% and TF32 gained 98.4%;
the controls were unchanged. All 20 before/after full-output digests matched,
and all numerical checks passed. The complete stock-boost matrix suite's
mean sampled power rose from 248.94 W to 295.17 W; its median SM clock fell
from 2760 MHz to 2580 MHz under the unchanged 320 W limit.

Strata 0.2.8 / engine 0.1.54, native IQ3_XXS, one slot, MTP 4, INT8 KV,
20480 resident KV cells, 262144 configured context and 1024 MiB VRAM reserve:

| Metric, median of three requests | Before token/s | After token/s | Change |
| --- | ---: | ---: | ---: |
| 427-token prompt processing | 590.8 | 623.4 | +5.5% |
| 12332-token prompt processing | 387.4 | 419.1 | +8.2% |
| Decode after short prompt | 124.0 | 120.7 | -2.7% |
| Decode after long prompt | 122.0 | 123.4 | +1.1% |

The application used identical request hashes, token counts and private
configuration in both phases, with no prefix reuse. Its automatic resident
RAM budget was 17.90 GiB before and 18.07 GiB after, and adaptive expert
placement remained enabled. These application observations include host
memory and routing effects; the matrix results isolate the tensor gain more
directly. Decode differences are within the observed run variation.
Five of six generated-response hashes differed, so the application test does
not establish text or quality equivalence. The matching matrix digests refer
only to the matrix fixtures.

After unlocking, the 30 GiB CUDA VRAM pattern test, OpenCL, Vulkan submission
and readback, and OpenGL/EGL rendering passed. There were no Xid, AER or OOM
errors during the tested boot. The pre-test Strata state was restored:
enabled for boot, currently stopped.
