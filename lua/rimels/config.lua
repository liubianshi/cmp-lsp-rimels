local default = require "rimels.default_opts"
local probes = require "rimels.probes"
local detectors = require "rimels.english_environment_detectors"
local M = {}

function M.update_option(user)
  if not (user and next(user)) then
    return default
  end

  local opts = {}
  for key, value in pairs(default) do
    if user[key] then
      if key == "cmd" and type(user[key]) == "string" then
        opts[key] = { user[key] }
      elseif key == "cmd" and type(user[key]) == "function" then
        opts[key] = user[key]
      elseif type(user[key]) ~= type(value) then
        error(key .. " must be " .. type(value))
      elseif type(value) == "table" then
        opts[key] = vim.tbl_extend("force", value, user[key])
      else
        opts[key] = user[key]
      end
    else
      opts[key] = value -- 如果 user 表格中没有对应 key，则保持默认值不变
    end
  end

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
