# Local setup (this PC)

Avalon on the Bazzite desktop (RX 7900 XTX 24 GB, i5-13600K, 96 GB DDR4-3200 as 3 x 32 GB), served to the DeepSeek Harness (dsh) next to
fork-strata's Brilliance Flash-Next. Only one local model runs at a time: they share port 8080 and the GPU.

| file | what |
|---|---|
| `local/build.sh` | builds `build/bin/llama-server` for gfx1100 on the host |
| `local/avalon` | the launcher: closes other model servers, starts Avalon, opens `dsh web` on the `avalon` route; closing it unloads the model |
| `local/desktop/` | the taskbar launcher (`avalon-flash-next.desktop`) and its icon |

## Install

1. Build: `local/build.sh` (10-20 minutes). The host has no system ROCm, so it compiles with the TheRock ROCm 7.10 SDK
   already in `fork-strata/.venv` (`AVALON_ROCM_SITE` points elsewhere). The upstream `install.sh` wants
   `/opt/rocm/bin/amdclang++` and is not used. The web page's gzip step is off: it resolves `/home` to `/var/home` and fails.
2. Model (~89.7 GiB, the README's IQ3_KS hybrid + MTP head + `moe-cache-ranking.bin`), to `~/Avalon-models`:
   `uvx --from 'huggingface_hub[hf_xet]' hf download freriadoc/Qwen3.8-Flash-Next-Avalon-GGUF --local-dir ~/Avalon-models/Qwen3.8-Flash-Next-Avalon-GGUF --exclude '*.jpg'`
3. dsh: the `avalon` and `avalon-summary` routes are in `tool-deepseek-setup/dsh/providers.txt`; `AVALON_API_KEY=local`
   in `~/.dsh/.env`, then re-run that repo's `install.sh`.
4. Taskbar: copy `local/desktop/avalon-flash-next.desktop` to `~/.local/share/applications/` and the `.svg` to
   `~/.local/share/icons/hicolor/scalable/apps/`, run `kbuildsycoca6`, then pin it (right-click the running icon, Pin).

## Use

- Click **Avalon Flash-Next** in the taskbar, or run `local/avalon`. `local/avalon up | down | status | logs | print-cmd`.
- Before loading it closes: any other `dsh web` (Strata's launcher and swh unload their model when theirs ends), whatever
  serves port 8080, LM Studio's loaded models, ComfyUI and the CoolerControl window. Games and browsers stay open: close
  a running game first. If Avalon is already up, the click reuses it. Closing the window (or Ctrl+C) unloads it, even
  mid-load; the PC cannot sleep while it is loaded.
- The model is the stock Qwen3.8-Flash-Next (not abliterated like Brilliance), 256K context, no picture reader.
- The first start reads the model from disk; later starts come from the page cache while RAM allows.
- The launcher pins the experts (`GGML_CUDA_MOE_PIN=1`, Avalon's default) when 70 GiB of RAM or more is free once the
  other model servers are closed, else it leaves them unpinned and says so. Set `GGML_CUDA_MOE_PIN` to force either.

## Measured (2026-11-01)

The same dsh headless task each time ("create fib.py ... run it"), MTP on, 256K context. "Cold" = the model evicted from
the page cache before the server starts.

| RAM | experts pinned | agent task cold / warm | generation (512 tok) | prefill (21.5K tok) |
|---|---|---|---|---|
| 64 GB | yes | 7 min 4 s | 60 - 112 t/s, SSD-bound | 96 - 1,175 t/s |
| 64 GB | no | 4 min 59 s | not measured | not measured |
| 96 GB | no | 37 s / 23 s | 76 - 92 t/s | 1,111 - 1,136 t/s |
| 96 GB | yes | **30 s / 18 s** | **92 - 102 t/s** | **1,118 - 1,140 t/s** |

- 64 GB: the 89.7 GiB model does not fit, so experts were re-read from the SSD in 4 KiB page faults (Avalon advises its
  lazy expert ranges `POSIX_MADV_RANDOM`, src/llama-mmap.cpp), ~80 MB/s, and agent turns stalled (one at 0.65 t/s).
  Pinned, KFD's restore worker (kworker events_freezable) also faulted ~20,000 pages/s back in while idle. Unpinning
  stopped the idle churn, not the stalls.
- 96 GB: no SSD reads once loaded, no idle churn with the experts pinned; loading from disk takes 17 - 20 s.
- The third stick runs in Intel flex mode: 64 GB dual-channel (~31 GB/s read measured) and 32 GB single-channel
  (~20 GB/s). Generation peaked at 112 t/s on 64 GB against 102 here, likely the single-channel part.

## Not done yet

- Tuning for this PC: the server runs the author's settings (6 threads on the P-cores, 2 MTP draft tokens). A sweep of
  threads (6 / 8 / 12) x draft tokens (2 / 3) on the benchmarks above may gain a few percent.
- Updating from upstream: `git remote add upstream https://github.com/freriadoc/Avalon`, merge `upstream/main` (a real
  merge, not a squash), then `local/build.sh`. Upstream never touches `local/`.
