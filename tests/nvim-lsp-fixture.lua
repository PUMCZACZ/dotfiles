local specs = dofile('home/nvim/lua/plugins/lsp.lua')

local lsp_spec
for _, spec in ipairs(specs) do
  if spec[1] == 'mason-org/mason-lspconfig.nvim' then
    lsp_spec = spec
    break
  end
end

assert(lsp_spec, 'brak konfiguracji mason-lspconfig.nvim')

local dependencies = {}
for _, dependency in ipairs(lsp_spec.dependencies or {}) do
  local name = type(dependency) == 'table' and dependency[1] or dependency
  dependencies[name] = true
end

assert(dependencies['mason-org/mason.nvim'], 'brak zależności mason.nvim')
assert(dependencies['neovim/nvim-lspconfig'], 'brak zależności nvim-lspconfig')

local expected_servers = {
  gopls = 'gopls@v0.23.0',
  phpactor = 'phpactor@2026.07.22.0',
  roslyn_ls = 'roslyn_ls@5.11.0-1.26380.4',
  ts_ls = 'ts_ls@6.0.0',
}

local installed_servers = {}
for _, server in ipairs(lsp_spec.opts.ensure_installed or {}) do
  installed_servers[server] = true
end

local enabled_servers = {}
for _, server in ipairs(lsp_spec.opts.automatic_enable or {}) do
  enabled_servers[server] = true
end

for server, pinned_server in pairs(expected_servers) do
  assert(installed_servers[pinned_server], 'serwer nie jest instalowany w przypiętej wersji: ' .. pinned_server)
  assert(enabled_servers[server], 'serwer nie jest włączany: ' .. server)
end

for installed_server in pairs(installed_servers) do
  local expected = false
  for _, pinned_server in pairs(expected_servers) do
    expected = expected or installed_server == pinned_server
  end
  assert(expected, 'nieoczekiwany instalowany serwer: ' .. installed_server)
end

for server in pairs(enabled_servers) do
  assert(expected_servers[server], 'nieoczekiwany włączany serwer: ' .. server)
end

print('PASS konfiguracja Neovim LSP obejmuje Go, PHP, C#, JavaScript i TypeScript')
