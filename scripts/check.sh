#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
lua tests/run.lua
for path in src/POSEhusker/*.lua; do luac -p "$path"; done
luacheck src/POSEhusker
