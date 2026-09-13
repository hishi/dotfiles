#!/usr/bin/env bash
state_file="$HOME/.cache/lazygit/branch-log-all-mode"
ref="$1"
fmt='%C(auto)%h%Creset %s %C(auto)%d%Creset'

if [ -f "$state_file" ]; then
  exec git log --graph --decorate --color=always --pretty="$fmt" --all
fi

case "$ref" in
  refs/heads/*)
    name="${ref#refs/heads/}"
    upstream=$(git rev-parse --abbrev-ref "$name@{u}" 2>/dev/null)
    if [ -n "$upstream" ]; then
      exec git log --graph --decorate --color=always --pretty="$fmt" "$ref" "refs/remotes/$upstream" --
    fi
    exec git log --graph --decorate --color=always --pretty="$fmt" "$ref" --
    ;;
  refs/remotes/*)
    short="${ref#refs/remotes/}"
    name="${short#*/}"
    if git show-ref --verify --quiet "refs/heads/$name"; then
      exec git log --graph --decorate --color=always --pretty="$fmt" "$ref" "refs/heads/$name" --
    fi
    exec git log --graph --decorate --color=always --pretty="$fmt" "$ref" --
    ;;
  *)
    exec git log --graph --decorate --color=always --pretty="$fmt" "$ref" --
    ;;
esac
