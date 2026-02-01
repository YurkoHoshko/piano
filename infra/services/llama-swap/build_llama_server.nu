#!/usr/bin/env nu

# Build a GPU-enabled llama-server binary inside the CUDA container and
# drop artifacts into infra/services/llama-swap/out (or $LLAMA_CPP_OUT).
let repo_root = (pwd)
let src = ($env.LLAMA_CPP_SRC? | default "~/Code/ik_llama.cpp" | path expand)
let artifacts = ($env.LLAMA_CPP_OUT? | default ([$repo_root "infra" "services" "llama-swap" "out"] | path join) | path expand)
let image = ($env.LLAMA_CPP_IMAGE? | default "llama-swap-cuda:base")
let service_dir = ([$repo_root "infra" "services" "llama-swap"] | path join)
let llama_swap_version = ($env.LLAMA_SWAP_VERSION? | default "v174")

mkdir $artifacts

print $"Building base image: ($image)"
docker build -t $image -f $"($service_dir)/Dockerfile.base" $repo_root

let build_steps = [
  "set -euo pipefail"
  "cd /ik_llama.cpp"
  "apt update"
  "DEBIAN_FRONTEND=noninteractive apt install -y cmake ccache git libsqlite3-dev"
  "git config --global --add safe.directory /ik_llama.cpp"
  "git pull"
  "cmake -B ./build -DGGML_CUDA=ON -DGGML_BLAS=OFF"
  "cmake --build ./build --config Release -j $(nproc)"
  "cp ./build/bin/llama-server /out/llama-server"
  "cp ./build/src/libllama.so /out/libllama.so"
  "cp ./build/ggml/src/libggml.so /out/libggml.so"
  "cp ./build/examples/mtmd/libmtmd.so /out/libmtmd.so"
]

let build_script = ($build_steps | str join " && ")

let docker_args = [
  "run" "--rm" "--gpus" "all"
  "--pull" "never"
  "-v" $"($src):/ik_llama.cpp"
  "-v" $"($artifacts):/out"
  "--name" "iktest"
  $image
  "bash" "-lc" $build_script
]

print $"Building llama-server from ($src) into ($artifacts)"
docker ...$docker_args

print ("Building llama-swap image via docker build (LLAMA_SWAP_VERSION=" + $llama_swap_version + ")")
docker build -t "local/llama-swap:custom" $"--build-arg=LLAMA_SWAP_VERSION=($llama_swap_version)" -f $"($service_dir)/Dockerfile" $service_dir
