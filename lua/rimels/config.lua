local default = require "rimels.default_opts"
local probes = require "rimels.probes"
local detectors = require "rimels.english_environment_detectors"
local M = {}

function M.update_option(user)
  if not (user and next(user)) then
    return default
  end

  if user.cmd and type(user.cmd) == "string" then
    user.cmd = { user.cmd }
  end

  local opts = vim.tbl_deep_extend("force", default, user)

  for name, probe in pairs(probes) do
    if vim.fn.index(opts.probes.ignore, name) < 0 then
      opts.probes.using[name] = probe
    end
  end

  opts.probes.using =
    vim.tbl_extend("force", opts.probes.using, opts.probes.add)

  opts.detectors = {
    with_treesitter = vim.tbl_extend(
      "force",
      detectors.with_treesitter,
      opts.detectors.with_treesitter or {}
    ),
    with_syntax = vim.tbl_extend(
      "force",
      detectors.with_syntax,
      opts.detectors.with_syntax or {}
    ),
  }

  return opts
end

return M
