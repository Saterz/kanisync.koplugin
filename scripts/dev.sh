#!/bin/bash
set -e

PLUGIN_NAME=$(basename "$PWD")

rsync -a --delete \
    --include="README.md" \
    --include="LICENSE" \
    --include="*.lua" \
    --exclude="*" \
    "./" "./koreader/plugins/$PLUGIN_NAME"

./koreader/kodev run
