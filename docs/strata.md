# Strata from source on Gentoo

`sci-ml/strata-0.2.8` builds Strata engine 0.1.54 and its Python API server from
commit `870aedd9e1ebe1c91f94da93b59af17729f6c5c0`. The CPU vision encoder and
native expert kernels use llama.cpp commit
`3cf03257f219afbe7334045ff7c6a06ac68c627d`. Both source archives are pinned in
the ebuild and Manifest; the build does not fetch subprojects or use pip.

This package reproduces an existing 0.2.8 deployment. It does not track the
upstream latest release. Update the pinned sources and review both patches
together when upgrading.

## Build

Select a supported Python implementation and enable the desired USE flags:

```text
# /etc/portage/package.accept_keywords/strata
sci-ml/strata ~amd64

# /etc/portage/package.use/strata
sci-ml/strata systemd vision test
```

For an EPYC 7302P and an RTX 4080 SUPER, use a package-specific environment:

```text
# /etc/portage/package.env/strata
sci-ml/strata strata-native.conf
```

```bash
# /etc/portage/env/strata-native.conf
CFLAGS="-O3 -march=native -mtune=native -fomit-frame-pointer -pipe"
CXXFLAGS="${CFLAGS}"
NVCCFLAGS="-O3"
CUDAARCHS="89-real"
MAKEOPTS="-j4 -l8"
CMAKE_VERBOSE=OFF
FEATURES="${FEATURES} test"
```

`CUDAARCHS` accepts CMake's semicolon-separated architecture list. Select the
installed GPU's architecture; 89 is Ada, while the reference deployment used
120 (Blackwell). If unset, CMake detects the build host's GPU. `-real` builds
native device code for that GPU. These native CPU/GPU binaries should be
rebuilt for different hardware. The four-job limit leaves RAM for nvcc on a
32 GiB host. No relaxed floating-point flags are added.

```sh
emerge -av sci-ml/strata
strata --version
nvidia-smi
```

NumPy's `lapack` flag is optional for this server's tokenizer/array work;
the C++ inference engine uses its own CPU kernels and CUDA, not NumPy BLAS.
Disable that flag only if the host's other NumPy users do not need LAPACK.

## Files and service

| Path | Purpose |
| --- | --- |
| `/opt/strata` | Portage-managed code, engine and CPU vision reader |
| `/var/lib/strata/data` | Model weights and prepared model data; also `/opt/strata/data` |
| `/usr/share/strata/data` | Small profiles and metadata shipped in the source archive |
| `/etc/strata/server.example.json` | Inactive, loopback-only example, without a credential |
| `/etc/strata/server.json` | Operator's private run configuration |
| `/var/log/strata` | Engine log directory |
| `strata.service` | Optional systemd service, running as the `strata` account |

The ebuild installs no model weights and does not enable the service. Supply
the matching GGUF shards, prepared dense pack/tokenizer, expert profile and
any optional MTP/vision/projection files before starting it. Do not copy
the reference machine's CUDA executable or Python virtual environment.
Grant the `strata` account read access to model files and traversal of their
directories; reference packs can contain private directories that rsync preserves.

Copy the example to `server.json`, edit it for the selected model, and give
it owner `strata:strata` and mode `0600`. `/etc/strata` is owned by the service
account because Strata writes its adjacent shared-settings file there.
Set a fresh `api_key` before binding beyond loopback. Keep credentials and
private run configurations out of this repository.

```sh
systemctl enable --now strata.service
systemctl status strata.service
journalctl -u strata.service -b
```

Use Portage to update or remove the package. Strata's source installer and
internal updater manage a different installation layout and should not be
used to replace these package-managed files.

## 32 GiB GPU and 31 GiB host RAM

The reference IQ3_XXS model has about 43 GB of experts; loading all of them
into host RAM does not fit this machine. `--resident-experts` maps the GGUF
and copies the complement of the GPU expert cache into RAM. It retains
headroom and falls back to a smaller resident tier when necessary. The
remaining file tier is backed by the NVMe drive. The startup log reports
what actually fits; a large BAR1 window does not make host RAM unnecessary.

The example uses the automatic GPU expert cache, a 1024 MiB VRAM reserve,
INT8 KV streaming with a 20480-token GPU-resident window, a 262144-token
maximum context, one slot and no parked conversation cache. Context capacity
and actual request performance still need a live-model check. MTP, CPU
vision and speed projection can be enabled using the matching reference
data and their existing engine flags. CPU workers default to physical cores
and should be measured before overriding `--pool-workers`.

## Reference patches

The ebuild applies two small patches carried by the reference deployment:

* The web projection switch starts off.
* An explicitly registered `<model>-sp` alias selects speed projection,
  while the canonical model defaults to off. Explicit request parameters
  override the model default. Both names share the same loaded engine.

The alias patch includes request-precedence tests. `USE=test` runs those
tests during emerge. Register the alias in the private configuration only
after supplying the projection vector and its engine arguments. Upstream
behavior is preserved for aliases that do not follow this opt-in convention.

After model startup, verify authenticated `/health` and `/v1/models`, then
send real generation requests to the canonical and `-sp` names. Check the
OpenAI, Responses and Anthropic adapters actually used by clients. Test an
image with the CPU vision reader when vision is enabled. Record memory,
GPU use, generation timings and kernel errors; a listening port alone is
not a successful inference test.
