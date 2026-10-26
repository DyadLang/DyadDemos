#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -d .source/.git ]; then
    git clone --depth 1 --branch v3.5.0-rc2 https://github.com/JuliaComputing/dyad-lang.git .source
fi
expected=a24a2240667872d432a3b86c4db1240d77150e35
actual=$(git -C .source rev-parse HEAD)
if [ "$actual" != "$expected" ]; then
    echo "Expected compiler $expected, found $actual" >&2
    exit 1
fi
npm ci --cache .npm-cache
node build.mjs
./dyad --version
