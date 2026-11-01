#!/usr/bin/env bash
# Build Avalon's llama-server for this PC (RX 7900 XTX, gfx1100) on the Bazzite host.
#
# The host has no system ROCm (/opt/rocm); fork-strata's .venv already holds AMD's TheRock ROCm 7.10 SDK with the
# gfx110X libraries, so this reuses it instead of installing a second ~10 GB copy. install.sh's own build step wants
# /opt/rocm/bin/amdclang++, which is why it is not used here.
#
#   local/build.sh            configure (once) and build llama-server into build/bin
set -euo pipefail

# The host has the C++ compiler and the GPU; from the Claude desktop container, hop out first (as swh does).
if [ -f /run/.containerenv ] && command -v distrobox-host-exec >/dev/null; then
  mapfile -t pass < <(env | grep -E '^AVALON_ROCM_SITE=')   # host-exec does not forward the environment
  exec distrobox-host-exec env "${pass[@]}" "$(readlink -f "$0")" "$@"
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SP=${AVALON_ROCM_SITE:-$HOME/Projects/fork-strata/.venv/lib/python3.14/site-packages}
RR=$SP/_rocm_sdk_devel
LIBS=$SP/_rocm_sdk_libraries_gfx110X_dgpu
[ -x "$RR/llvm/bin/clang++" ] || { echo "no TheRock ROCm SDK in $SP (set AVALON_ROCM_SITE)" >&2; exit 1; }
BITCODE=$RR/lib/llvm/amdgcn/bitcode; [ -d "$BITCODE" ] || BITCODE=$RR/amdgcn/bitcode

export HIP_PLATFORM=amd ROCM_PATH=$RR HIP_PATH=$RR
export PATH=$RR/bin:$RR/llvm/bin:$PATH
export LD_LIBRARY_PATH=$RR/lib:$LIBS/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

cmake -S "$ROOT" -B "$ROOT/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100 \
  -DCMAKE_HIP_COMPILER="$RR/llvm/bin/clang++" -DCMAKE_HIP_COMPILER_ROCM_ROOT="$RR" \
  -DCMAKE_PREFIX_PATH="$RR;$LIBS" \
  -DCMAKE_HIP_FLAGS="--rocm-path=$RR --rocm-device-lib-path=$BITCODE" \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_UI_GZIP=OFF `# its gzip step resolves /home to /var/home (Bazzite) and then cannot find the files` \
  > "$ROOT/build-configure.log" 2>&1 || { tail -30 "$ROOT/build-configure.log"; exit 1; }
cmake --build "$ROOT/build" -j"$(nproc)" --target llama-server > "$ROOT/build.log" 2>&1 \
  || { tail -40 "$ROOT/build.log"; exit 1; }
echo "built $ROOT/build/bin/llama-server"
