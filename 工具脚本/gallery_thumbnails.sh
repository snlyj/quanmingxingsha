#!/usr/bin/env bash
# 更新卡图或立绘后，用 ImageMagick 重新生成图鉴缩略图。
set -eu
cd "$(dirname "$0")/../game/assets"

make_thumbnails() {
  local kind=$1 bound=$2 source
  mkdir -p "thumbnails/$kind"
  for source in "$kind"/*.webp; do
    magick "$source" -resize "${bound}>" -strip -quality 82 "thumbnails/$source"
  done
}

make_thumbnails cards 144x208
make_thumbnails cg 384x512
