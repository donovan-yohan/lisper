#!/usr/bin/env bash
set -euo pipefail

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  fi
}

require_tool git
require_tool cmake
require_tool curl

ensure_sdl2() {
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists sdl2; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    if ! brew list --formula sdl2 >/dev/null 2>&1; then
      printf 'Installing SDL2 via Homebrew\n'
      brew install sdl2
    fi
    return 0
  fi

  printf 'SDL2 is required for whisper-stream. Install it with Homebrew: brew install sdl2\n' >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
tools_dir="$repo_root/.tools"
whisper_repo_dir="$tools_dir/whisper.cpp"
whisper_build_dir="$whisper_repo_dir/build"
model_dir="$tools_dir/models"
model_name="tiny.en"
model_path="$model_dir/ggml-${model_name}.bin"
stream_binary="$whisper_build_dir/bin/whisper-stream"
repo_url="https://github.com/ggml-org/whisper.cpp.git"
model_script="$whisper_repo_dir/models/download-ggml-model.sh"

mkdir -p "$tools_dir" "$model_dir"
ensure_sdl2

if [ ! -d "$whisper_repo_dir/.git" ]; then
  printf 'Cloning whisper.cpp into %s\n' "$whisper_repo_dir"
  git clone --depth 1 "$repo_url" "$whisper_repo_dir"
fi

printf 'Building whisper-stream in %s\n' "$whisper_build_dir"
cmake -S "$whisper_repo_dir" -B "$whisper_build_dir" -DCMAKE_BUILD_TYPE=Release -DWHISPER_SDL2=ON
cmake --build "$whisper_build_dir" --config Release --target whisper-stream --parallel

if [ ! -f "$model_path" ]; then
  printf 'Downloading %s model into %s\n' "$model_name" "$model_dir"
  bash "$model_script" "$model_name" "$model_dir"
fi

if [ ! -x "$stream_binary" ]; then
  printf 'Expected whisper-stream binary was not produced: %s\n' "$stream_binary" >&2
  exit 1
fi

if [ ! -f "$model_path" ]; then
  printf 'Expected model file was not produced: %s\n' "$model_path" >&2
  exit 1
fi

resolved_stream_binary="$(cd "$(dirname "$stream_binary")" && pwd -P)/$(basename "$stream_binary")"
resolved_model_path="$(cd "$(dirname "$model_path")" && pwd -P)/$(basename "$model_path")"

printf 'whisper-stream: %s\n' "$resolved_stream_binary"
printf 'model: %s\n' "$resolved_model_path"
