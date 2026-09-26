# ophub-kernel 6.18.54-r1 configuration validation

Validated on 2026-09-27. This revision changes package/configuration support;
the r1 kernel has not yet been fully compiled, installed or booted.

- Actual Portage unpack/prepare/configure ran on native ARM64/GCC 16.2.0 with
  `USE="debug savedconfig test"` and the TPM312 custom config.
- The configured release is `6.18.54-ophub-gentoo-r1`.
- DWARF5, kernel BTF, module BTF and FUNCTION_TRACER are enabled.
- `olddefconfig` selects DYNAMIC_FTRACE, WITH_ARGS, WITH_CALL_OPS and
  WITH_DIRECT_CALLS; the 4 KiB page configuration remains enabled.
- The package now checks DWARF5/BTF settings after olddefconfig instead of
  silently producing a debug build without BTF. Split/reduced debug options
  are disabled when USE=debug to satisfy BTF dependencies.
- TPM312's actual emerge preview selects r1 as a new slot with debug/savedconfig.
  Existing r0 modules and headers are retained. The preview used a temporary
  overlay supplied only to that process; no kernel installation was performed.
- r1 savedconfig and version-specific USE settings were written on the build
  host and TPM312. The r0 savedconfig, world and boot configuration were checked
  unchanged. The running kernel remains `6.18.54-ophub-gentoo-r0`.

The initial r0 full build, binary installation, real hardware boot and external
module tests remain separate evidence. r0 also passed the Panfrost 120-frame
render/readback test. They do not substitute for r1 build/boot validation or a
future `bpftune -S` test under the BTF-enabled kernel.
