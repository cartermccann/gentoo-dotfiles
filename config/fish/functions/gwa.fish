# Git worktrees as `repo--branch` sibling directories.
# Named gwa/gwr rather than ga/gd — those are taken by the git add / git diff
# aliases in config.fish.
function gwa --description "git worktree add -b <branch> ../<repo>--<branch>"
    if test (count $argv) -ne 1
        echo "usage: gwa <branch>" >&2
        return 1
    end
    set -l root (git rev-parse --show-toplevel); or return 1
    set -l dir (dirname $root)/(basename $root)--$argv[1]
    git worktree add -b $argv[1] $dir; and cd $dir
end
