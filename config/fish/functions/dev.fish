# Three-pane dev layout: editor left, two shells stacked on the right.
# Pane indices assume base-index 1 / pane-base-index 1 (config/tmux/tmux.conf).
function dev --description "tmux dev layout in the current directory"
    if tmux has-session -t dev 2>/dev/null
        tmux attach -t dev
        return
    end
    tmux new-session -d -s dev -c (pwd)
    tmux split-window -h -p 40 -c (pwd)
    tmux split-window -v -p 50 -c (pwd)
    tmux send-keys -t dev:1.1 nvim Enter
    tmux select-pane -t dev:1.1
    tmux attach -t dev
end
