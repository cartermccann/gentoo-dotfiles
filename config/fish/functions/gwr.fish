# Tear down the worktree you are standing in, and its branch with it.
# Only ever acts on a directory named `<repo>--<branch>` — the naming
# convention IS the safety check, so running this in a normal checkout is a
# no-op rather than a branch deletion.
function gwr --description "remove the current worktree dir + its branch"
    set -l wt $PWD
    set -l dir (basename $wt)
    set -l parts (string split --max 1 -- '--' $dir)
    if test (count $parts) -ne 2; or test -z "$parts[2]"
        echo "gwr: '$dir' is not a repo--branch worktree dir" >&2
        return 1
    end
    set -l branch $parts[2]
    # The main checkout is the sibling with the --branch suffix stripped. Ask
    # git for it rather than assuming: --show-toplevel would just hand back the
    # worktree we are deleting.
    # git lists the main working tree first, always.
    set -l main (git worktree list --porcelain | string replace -f 'worktree ' '' | head -1)
    if test -z "$main"
        echo "gwr: not inside a git worktree" >&2
        return 1
    end
    gum confirm "Remove worktree $dir and delete branch $branch?"; or return 1
    cd ..
    # Absolute path: a bare basename would be resolved relative to $main by
    # `git -C`, not relative to where we started.
    git -C $main worktree remove $wt --force
    and git -C $main branch -D $branch
end
