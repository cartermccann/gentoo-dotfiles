# atlas fish config — at parity with kronos (~/dotfiles home/shell.nix).
#
# Everything interactive is guarded by `command -q`: this file is symlinked
# into place by the dotfiles phase, which can run before the packages phase
# has finished, and a fish that errors on startup is a fish you cannot use to
# fix the packages phase.
#
# Deliberately NOT ported from kronos: the nix aliases (nrs/update), the
# ollama chat aliases and heavy/heavy-stop (no local model server here), and
# the fastfetch greeting (needs scripts/ff-cascade.sh + a fastfetch config).

# ── PATH ───────────────────────────────────────────────────────
fish_add_path -g ~/.npm-global/bin
# Vendor CLIs that ship their own installers and live under $HOME
# (phases/32-devtools.sh). Added here rather than by their install scripts, so
# the entry exists in exactly one place instead of appended to a shell rc too.
fish_add_path -g ~/.fly/bin
fish_add_path -g ~/apps/google-cloud-sdk/bin
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
    command -q direnv;   and direnv hook fish | source

    # fzf ships its fish bindings as a plain file rather than an init
    # subcommand — sourcing it defines fzf_key_bindings, calling it installs
    # C-t (files), C-r (history), M-c (cd).
    # NOTE: atuin also binds C-r and initialises after this, so atuin wins
    # there by design; C-t and M-c are fzf's.
    if command -q fzf; and test -f /usr/share/fzf/key-bindings.fish
        source /usr/share/fzf/key-bindings.fish
        fzf_key_bindings
    end

    # Autosuggestion colour — visible but subtle on the near-black glass
    set -U fish_color_autosuggestion 90909a

    # ── Modern replacements ────────────────────────────────────
    command -q eza; and alias ls 'eza --icons'; and alias ll 'eza -la --icons'
    command -q bat; and alias cat 'bat'
    command -q rg;  and alias grep 'rg'
    command -q duf; and alias df 'duf'
    command -q yazi; and alias y 'yazi'
    command -q glow; and alias md 'glow'
    command -q tv;   and alias tvf 'tv files'

    # ── Git ────────────────────────────────────────────────────
    # (worktree helpers gwa/gwr live in functions/, autoloaded)
    alias gs 'git status'
    alias ga 'git add'
    alias gc 'git commit'
    alias gp 'git push'
    alias gl 'git log --oneline --graph'
    alias gd 'git diff'
    alias gb 'git branch'

    # ── Docker ─────────────────────────────────────────────────
    alias dc 'docker compose'
    alias dps 'docker ps'
    alias dimg 'docker images'
    alias dlog 'docker logs'
end
