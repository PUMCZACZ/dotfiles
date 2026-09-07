return {
  {
    'mason-org/mason-lspconfig.nvim',
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} },
      'neovim/nvim-lspconfig',
    },
    opts = {
      ensure_installed = {
        'gopls@v0.23.0',
        'phpactor@2026.07.22.0',
        'roslyn_ls@5.11.0-1.26380.4',
        'ts_ls@6.0.0',
      },
      automatic_enable = {
        'gopls',
        'phpactor',
        'roslyn_ls',
        'ts_ls',
      },
    },
  },
}
