#!/usr/bin/env bash
# Prints 1 while the screen is being captured: every recorder on KWin Wayland goes
# through the portal, and PipeWire nodes carry `screencast` in media.name.
if pw-dump 2>/dev/null \
    | jq -e 'any(.[]; (.info.props."media.name" // "") | test("screencast"; "i"))' >/dev/null 2>&1; then
    echo 1
else
    echo 0
fi
