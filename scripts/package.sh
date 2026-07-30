#!/bin/bash

PLUGIN_VERSION=${1:-development}
PLUGIN_NAME=$(basename "$PWD")

if [[ ! "$PLUGIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] &&
    [[ "$PLUGIN_VERSION" != "development" ]]; then
    echo "Invalid plugin version: $PLUGIN_VERSION" >&2
    exit 1
fi

mkdir -p "dist/$PLUGIN_NAME"
rsync -av \
    --exclude="kani_config.lua" \
    --include="*/" \
    --include="*.lua" \
    --exclude="*" \
    ./src/ "./dist/$PLUGIN_NAME"
cp README.md LICENSE "dist/$PLUGIN_NAME/"

sed -i -E \
    "s/^([[:space:]]*version[[:space:]]*=[[:space:]]*)\"[^\"]+\"/\\1\"$PLUGIN_VERSION\"/" \
    "dist/$PLUGIN_NAME/_meta.lua"

cd "dist" && zip -r "../$PLUGIN_NAME.zip" "$PLUGIN_NAME"
