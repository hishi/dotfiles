#!/usr/bin/env bash
state_file="$HOME/.cache/lazygit/branch-log-all-mode"
ref="$1"
fmt='%C(auto)%h%Creset %C(green)%ad%Creset %x01%an%x01 %x03%s%x03 %C(auto)%d%Creset%x02%H%x02'
common_args=(--graph --decorate --color=always --date="format:%Y-%m-%d %H:%M" --pretty="$fmt")

author_palette=(33 208 141 76 203 51 220 213)

render_log() {
  local head_hash line content full_hash
  local before rest name after ahash aidx acolor
  local sbefore srest subject safter
  head_hash=$(git rev-parse HEAD 2>/dev/null)

  while IFS= read -r line; do
    content="$line"
    full_hash=""

    if [[ "$content" == *$'\x02'*$'\x02'* ]]; then
      full_hash="${content#*$'\x02'}"
      full_hash="${full_hash%%$'\x02'*}"
      content="${content%%$'\x02'*}${content##*$'\x02'}"
    fi

    if [[ "$content" == *$'\x03'*$'\x03'* ]]; then
      sbefore="${content%%$'\x03'*}"
      srest="${content#*$'\x03'}"
      subject="${srest%%$'\x03'*}"
      safter="${srest#*$'\x03'}"
      if [[ -n "$full_hash" && "$full_hash" == "$head_hash" ]]; then
        subject=$(printf '\033[1;33m%s\033[0m' "$subject")
      fi
      content="${sbefore}${subject}${safter}"
    fi

    if [[ "$content" == *$'\x01'*$'\x01'* ]]; then
      before="${content%%$'\x01'*}"
      rest="${content#*$'\x01'}"
      name="${rest%%$'\x01'*}"
      after="${rest#*$'\x01'}"
      ahash=$(printf '%s' "$name" | cksum | cut -d' ' -f1)
      aidx=$(( ahash % ${#author_palette[@]} ))
      acolor="${author_palette[$aidx]}"
      content="${before}$(printf '\033[38;5;%sm<%s>\033[0m' "$acolor" "$name")${after}"
    fi

    printf '%s\n' "$content"
  done
}

run_log() {
  git log "${common_args[@]}" "$@" | render_log
}

if [ -f "$state_file" ]; then
  run_log --all
  exit
fi

case "$ref" in
  refs/heads/*)
    name="${ref#refs/heads/}"
    upstream=$(git rev-parse --abbrev-ref "$name@{u}" 2>/dev/null)
    if [ -n "$upstream" ]; then
      run_log "$ref" "refs/remotes/$upstream" --
      exit
    fi
    run_log "$ref" --
    ;;
  refs/remotes/*)
    short="${ref#refs/remotes/}"
    name="${short#*/}"
    if git show-ref --verify --quiet "refs/heads/$name"; then
      run_log "$ref" "refs/heads/$name" --
      exit
    fi
    run_log "$ref" --
    ;;
  *)
    run_log "$ref" --
    ;;
esac
