#!/bin/bash

PLUGIN_NAME=$(basename "$PWD")
mkdir -p "dist/$PLUGIN_NAME"
rsync -av \
    --exclude="config.lua" \
    --include="*/" \
    --include="*.lua" \
    --exclude="*" \
    ./src/ "./dist/$PLUGIN_NAME"
cp README.md LICENSE "dist/$PLUGIN_NAME/"
cd "dist" && zip -r "../$PLUGIN_NAME.zip" "$PLUGIN_NAME"
