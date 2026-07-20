#!/bin/bash
set -e

PLUGIN_NAME=$(basename "$PWD")

rsync -a --delete \
    --include="*/" \
    --include="*.lua" \
    --exclude="*" \
    "./src/" "./koreader/plugins/$PLUGIN_NAME"

./koreader/kodev run
