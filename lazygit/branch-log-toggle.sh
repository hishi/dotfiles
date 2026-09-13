#!/usr/bin/env bash
state_file="$HOME/.cache/lazygit/branch-log-all-mode"
mkdir -p "$(dirname "$state_file")"

if [ -f "$state_file" ]; then
  rm -f "$state_file"
else
  touch "$state_file"
fi
