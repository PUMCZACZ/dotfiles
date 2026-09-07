local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git', '--branch=stable', lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- Home Manager exposes the tracked lockfile through the read-only Nix store.
-- Give lazy.nvim a writable copy while keeping the repository lock authoritative.
local managed_lockfile = vim.fn.stdpath('config') .. '/lazy-lock.json'
local runtime_lock_directory = vim.fn.stdpath('state') .. '/lazy'
local runtime_lockfile = runtime_lock_directory .. '/lazy-lock.json'
vim.fn.mkdir(runtime_lock_directory, 'p')
assert(vim.fn.writefile(vim.fn.readfile(managed_lockfile), runtime_lockfile) == 0,
  'failed to prepare writable lazy.nvim lockfile')

require('lazy').setup('plugins', { lockfile = runtime_lockfile })  -- load every file in lua/plugins/
