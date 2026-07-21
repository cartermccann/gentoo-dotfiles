-- AI layer (revised 2026-06-10). One tool per layer:
--   completion menu  blink.cmp (LazyVim default; accepts on <CR>/<C-y>, never Tab)
--   tab autocomplete minuet-ai.nvim ghost text → local Ollama FIM
--                    (qwen2.5-coder:3b-base, ~1.9 GB resident on the 5070).
--                    <Tab> accepts the ghost via the blink keymap chain below.
--   agent            Claude Code in its tmux pane, bridged in via claudecode.nvim
--
-- Replaced GitHub Copilot (ai.copilot-native + ai.sidekick, removed from
-- lazyvim.json) — local FIM is free, private, and instant. Codex/Claude
-- subscriptions stay the AGENT layer (claudecode.nvim), not tab-complete:
-- their latency (1-5s) and per-token APIs are the wrong tool for inline FIM.
return {
  -- ghost-text mode: AI suggestions render inline, not as a blink menu source
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.g.ai_cmp = false
    end,
  },

  -----------------------------------------------------------------------------
  -- Local FIM tab-completion — minuet-ai.nvim → Ollama (OpenAI-compatible FIM)
  -----------------------------------------------------------------------------
  {
    "milanglacier/minuet-ai.nvim",
    event = "InsertEnter",
    opts = {
      provider = "openai_fim_compatible",
      n_completions = 1, -- single ghost suggestion (not a menu)
      context_window = 1024, -- chars of context sent; 3B model + GPU handles it
      throttle = 400, -- local model is fast — tighter than the 1000ms default
      debounce = 200,
      request_timeout = 3,
      notify = "warn", -- quiet unless something's actually wrong
      provider_options = {
        openai_fim_compatible = {
          -- `api_key` is the NAME of an env var that must merely exist; "TERM"
          -- is always set in a terminal, so the (irrelevant) key check passes.
          api_key = "TERM",
          name = "Ollama",
          end_point = "http://localhost:11434/v1/completions",
          model = "qwen2.5-coder:3b-base",
          optional = {
            max_tokens = 256,
            top_p = 0.9,
          },
        },
      },
      virtualtext = {
        auto_trigger_ft = { "*" }, -- ghost text as you type, Copilot-style
        auto_trigger_ignore_ft = {
          "neo-tree", "snacks_dashboard", "snacks_picker_input",
          "TelescopePrompt", "lazy", "mason", "help", "checkhealth", "oil",
        },
        -- <Tab> accept is handled in the blink keymap chain (below) so snippet
        -- jumps and a literal tab still fall through. These Alt maps are the
        -- explicit controls: force-accept, line/N-line accept, cycle, dismiss.
        keymap = {
          accept = "<A-A>",
          accept_line = "<A-a>",
          accept_n_lines = "<A-z>",
          prev = "<A-[>",
          next = "<A-]>",
          dismiss = "<A-e>",
        },
      },
    },
  },

  -- <Tab> chain: accept ghost → jump snippet → literal tab. blink owns the
  -- keymap so there's no raw-map conflict; the menu still accepts on <CR>/<C-y>.
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        ["<Tab>"] = {
          function()
            local ok, vt = pcall(require, "minuet.virtualtext")
            if ok and vt.action.is_visible() then
              vt.action.accept()
              return true
            end
          end,
          "snippet_forward",
          "fallback",
        },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },
    },
  },

  -----------------------------------------------------------------------------
  -- Agent layer — WebSocket MCP bridge: nvim hosts the server, the Claude Code
  -- CLI in tmux connects via `/ide` — selection/buffer context flows over,
  -- diffs come back as native nvim diff views. terminal.provider=none keeps
  -- Claude in tmux.
  -----------------------------------------------------------------------------
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal = { provider = "none" },
    },
    keys = {
      { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
      { "<leader>cb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add buffer to Claude context" },
      { "<leader>cd", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Claude diff" },
      { "<leader>cD", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Reject Claude diff" },
    },
  },
}
