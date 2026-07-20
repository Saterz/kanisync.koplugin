#!/bin/bash

PLUGIN_NAME=$(basename "$PWD")
mkdir -p "dist/$PLUGIN_NAME"
rsync -av --exclude="config.lua" --include="README.md" --include="LICENSE" --include="*.lua" --exclude="*" ./ "./dist/$PLUGIN_NAME"
cd "dist" && zip -r "../$PLUGIN_NAME.zip" "$PLUGIN_NAME"