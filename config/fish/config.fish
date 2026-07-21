# atlas fish config — starter (port more from kronos ~/dotfiles as you go)

# ── PATH ───────────────────────────────────────────────────────
fish_add_path -g ~/.npm-global/bin
fish_add_path -g ~/.local/bin
fish_add_path -g ~/.cargo/bin
fish_add_path -g ~/.bun/bin
fish_add_path -g ~/.deno/bin
fish_add_path -g ~/go/bin        # `go install` target (gum lives here)
fish_add_path -g ~/.opencode/bin

set -gx EDITOR nvim
set -gx VISUAL nvim

# ── Interactive tools ──────────────────────────────────────────
if status is-interactive
    command -q starship; and starship init fish | source
    command -q zoxide;   and zoxide init fish | source
    command -q atuin;    and atuin init fish | source

    # ── Aliases (mirrors kronos) ───────────────────────────────
    command -q eza; and alias ls 'eza --icons'; and alias ll 'eza -la --icons'
    command -q bat; and alias cat 'bat'
    command -q rg;  and alias grep 'rg'
    command -q duf; and alias df 'duf'
    command -q yazi; and alias y 'yazi'

    alias gs 'git status'
    alias ga 'git add'
    alias gc 'git commit'
    alias gp 'git push'
    alias gl 'git log --oneline --graph'
    alias gd 'git diff'
    alias gb 'git branch'
end
