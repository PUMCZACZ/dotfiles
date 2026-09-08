local specs = dofile('home/nvim/lua/plugins/lsp.lua')

local blink_spec
local lsp_spec
for _, spec in ipairs(specs) do
  if spec[1] == 'saghen/blink.cmp' then
    blink_spec = spec
  end
  if spec[1] == 'mason-org/mason-lspconfig.nvim' then
    lsp_spec = spec
  end
end

assert(blink_spec, 'brak konfiguracji blink.cmp')
assert(blink_spec.version == '1.*', 'blink.cmp nie używa stabilnej głównej wersji')
assert(blink_spec.opts.keymap.preset == 'super-tab', 'blink.cmp nie używa skrótów podobnych do IDE')

local expected_sources = {
  buffer = true,
  lsp = true,
  path = true,
  snippets = true,
}

local completion_sources = {}
for _, source in ipairs(blink_spec.opts.sources.default or {}) do
  completion_sources[source] = true
end

for source in pairs(expected_sources) do
  assert(completion_sources[source], 'brak źródła completion: ' .. source)
end

for source in pairs(completion_sources) do
  assert(expected_sources[source], 'nieoczekiwane źródło completion: ' .. source)
end

local menu_components = {}
local completion = blink_spec.opts.completion or {}
local menu = completion.menu or {}
local draw = menu.draw or {}
for _, column in ipairs(draw.columns or {}) do
  for _, component in ipairs(column) do
    if type(component) == 'string' then
      menu_components[component] = true
    end
  end
end

assert(menu_components.kind, 'menu completion nie rozróżnia tekstowo klas, metod i funkcji')
assert(menu_components.source_name, 'menu completion nie pokazuje źródła LSP/Buffer/Path/Snippets')

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
