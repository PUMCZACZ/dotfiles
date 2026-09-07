local managed_lock = { '{', '  "lazy.nvim": {}', '}' }
local created_directory
local copied_lines
local copied_path
local lazy_options

vim = {
  fn = {
    stdpath = function(kind)
      local paths = {
        config = '/managed/config',
        data = '/runtime/data',
        state = '/runtime/state',
      }
      return assert(paths[kind], 'nieoczekiwany stdpath: ' .. kind)
    end,
    system = function()
      error('lazy.nvim nie powinien być klonowany w tym fixture')
    end,
    mkdir = function(path, flags)
      created_directory = { path = path, flags = flags }
    end,
    readfile = function(path)
      assert(path == '/managed/config/lazy-lock.json', 'odczyt z niezarządzanego locka: ' .. path)
      return managed_lock
    end,
    writefile = function(lines, path)
      copied_lines = lines
      copied_path = path
      return 0
    end,
  },
  opt = {
    rtp = {
      prepend = function() end,
    },
  },
  uv = {
    fs_stat = function()
      return {}
    end,
  },
}

package.preload.lazy = function()
  return {
    setup = function(_, options)
      lazy_options = options
    end,
  }
end

dofile('home/nvim/lua/plugin.lua')

local runtime_lock = '/runtime/state/lazy/lazy-lock.json'
assert(created_directory, 'brak katalogu dla runtime locka')
assert(created_directory.path == '/runtime/state/lazy', 'brak katalogu dla runtime locka')
assert(created_directory.flags == 'p', 'katalog runtime locka nie jest tworzony rekurencyjnie')
assert(copied_path == runtime_lock, 'zarządzany lock nie jest kopiowany do runtime state')
assert(copied_lines == managed_lock, 'kopiowanie zmieniło zawartość locka')
assert(lazy_options.lockfile == runtime_lock, 'lazy.nvim nie używa zapisywalnego runtime locka')

print('PASS lazy.nvim używa zapisywalnej kopii zarządzanego locka')
