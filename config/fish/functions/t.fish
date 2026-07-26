function t --description "attach the one canonical tmux session, creating it if needed"
    tmux attach; or tmux new -s work
end
