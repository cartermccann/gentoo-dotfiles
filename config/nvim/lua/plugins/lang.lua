-- Language/LSP overrides
return {
  -- Use Nix-provided LSP binaries instead of Mason
  {
    "mason-org/mason.nvim",
    opts = { PATH = "append" },
  },
}
