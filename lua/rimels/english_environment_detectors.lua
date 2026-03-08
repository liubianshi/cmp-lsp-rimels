local M = {with_treesitter = {}, with_syntax = {}}

function M.with_treesitter.norg(info)
  info = info or vim.inspect_pos()
  local trees = info.treesitter
  local extmarks = info.extmarks
  local englist_env = false
  for _, ts in ipairs(trees) do
    if
      ts.capture == "neorg.markup.variable" or
      ts.capture == "neorg.markup.verbatim" or
      ts.capture == "neorg.markup.inline_math"
    then
      return true
    elseif ts.capture == "comment" then
      return false
    end
  end
  for _,ext in ipairs(extmarks) do
    if
      ext.opts and
      ext.opts.hl_group == "@neorg.tags.ranged_verbatim.code_block"
    then
      return true
    end
  end
  return englist_env
end

function M.with_treesitter.markdown(info)
  info = info or vim.inspect_pos()
  local trees = info.treesitter
  local englist_env = false
  for _, ts in ipairs(trees) do
    if
      ts.capture == "markup.math" or
      ts.capture == "markup.raw"
    then
      return true
    elseif ts.capture == "markup.raw.block" then
      englist_env = true
    elseif ts.capture == "comment" then
      return false
    end
  end
  return englist_env
end

function M.with_syntax.markdown(info)
  info = info or vim.inspect_pos()
  local syns = info.syntax
  local englist_env = false
  for _, syn in ipairs(syns) do
    local hl = syn.hl_group
    local hl_link = syn.hl_group_link
    if
      hl == "pandocLaTeXInlineMath" or
      hl == "pandocNoFormatted" or
      hl == "pandocOperator" or
      hl == "pandocLaTeXMathBlock"
    then
      return true
    elseif hl == "pandocDelimitedCodeBlock" then
      englist_env = true
    elseif hl_link == "Comment" then
      return false
    end
  end
  return englist_env
end

return M
