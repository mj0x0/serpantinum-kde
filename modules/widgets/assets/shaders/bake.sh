#!/usr/bin/env bash
# Upstream serpantinum's recipe; Vulkan reads only the SPIR-V variant. Outputs are committed.
cd "$(dirname "$0")" || exit 1
find . -name '*.frag' -print0 | xargs -0 -I{} /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o {}.qsb {}
echo "baked $(find . -name '*.frag' | wc -l) shader(s)"
