local M = {}

function M.with_treesitter(syns)
  syns = syns or {}
  local englist_env = false
  for _, ts in ipairs(syns) do
    if ts.capture == "markup.math" or ts.capture == "markup.raw" then
      return true
    elseif ts.capture == "markup.raw.block" then
      englist_env = true
    elseif ts.capture == "comment" then
      return false
    end
  end
  return englist_env
end

function M.with_pandoc_highlight(syns)
  syns = syns or {}
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
