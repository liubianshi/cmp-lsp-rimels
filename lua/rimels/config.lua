-- Module for handling rimels plugin option configuration and merging
local default = require "rimels.default_opts"
local probes = require "rimels.probes"
local detectors = require "rimels.english_environment_detectors"

local M = {}

--- Update and merge user options with default configuration
--- @param user table|nil User-provided options to merge with defaults
--- @return table Merged options configuration
function M.update_option(user)
  -- Return defaults if no user options provided or table is empty
  if not (user and next(user)) then
    return default
  end

  -- Normalize cmd option: convert string to table format for consistency
  if user.cmd and type(user.cmd) == "string" then
    user.cmd = { user.cmd }
  end

  -- Deep merge user options with defaults, user options take precedence
  local opts = vim.tbl_deep_extend("force", default, user)

  -- Configure probes: include all available probes except those explicitly ignored
  for name, probe in pairs(probes) do
    -- Only add probe if it's not in the ignore list
    if not vim.tbl_contains(opts.probes.ignore, name) then
      opts.probes.using[name] = probe
    end
  end

  -- Merge in any additional custom probes specified by user
  opts.probes.using = vim.tbl_extend("force", opts.probes.using, opts.probes.add)

  -- Configure detectors by merging default detectors with user-provided ones
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
