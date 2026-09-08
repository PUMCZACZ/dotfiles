return {
  {
    'saghen/blink.cmp',
    version = '1.*',
    opts = {
      keymap = { preset = 'super-tab' },
      completion = {
        menu = {
          draw = {
            columns = {
              { 'kind_icon' },
              { 'label', 'label_description', gap = 1 },
              { 'kind' },
              { 'source_name' },
            },
          },
        },
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
    },
  },
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
