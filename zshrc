export PATH="/opt/homebrew/opt/unzip/bin:$PATH"

alias vim='/opt/homebrew/bin/nvim'
alias vi='/opt/homebrew/bin/nvim'
alias view='/opt/homebrew/bin/nvim -R'

# alias ls='eza -alh --icons=auto --no-user'
# alias cat='bat --theme="Dracula"'
alias find='fd'
# alias cdf='cd "$(dirname "$(fzf --preview="bat --color=always {}")")"'
alias grep='rg'
alias ls='eza'
alias cat='bat'
export EZA_CONFIG_DIR=~/.config/eza

eval "$(mise activate zsh)"

# pure
fpath+=($HOME/.zsh/pure)

autoload -U promptinit; promptinit

# optionally define some options
PURE_CMD_MAX_EXEC_TIME=10

# change the path color
zstyle :prompt:pure:path color white

# change the color for both `prompt:success` and `prompt:error`
zstyle ':prompt:pure:prompt:*' color cyan

# turn on git stash status
zstyle :prompt:pure:git:stash show yes

prompt pure


# zsh-syntax-highlighting
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# zoxide
eval "$(zoxide init zsh)"


