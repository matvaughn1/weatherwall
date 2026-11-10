#!/bin/bash
# Compile the shaders into the package and (re)install the wallpaper plugin.
#   ./build.sh            build + install
#   ./build.sh --no-install          (QSB=/path/to/qsb to use another Qt's shader compiler)
set -euo pipefail
cd "$(dirname "$0")"
out=package/contents/ui/shaders
mkdir -p "$out" build
for s in sky clouds village patio photo glass; do
    # qsb has no #include: paste common.glsl in where the marker is
    sed -e '/\/\/#include common.glsl/{r shaders/common.glsl' -e 'd}' "shaders/$s.frag" > "build/$s.frag"
    "${QSB:-/usr/lib/qt6/bin/qsb}" --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$out/$s.frag.qsb" "build/$s.frag"
done
echo "shaders built"
[[ "${1:-}" == --no-install ]] && exit 0
kpackagetool6 -t Plasma/Wallpaper -u package 2>/dev/null || kpackagetool6 -t Plasma/Wallpaper -i package
