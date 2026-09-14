-- Declarative SceneNode composition for the Bitty Statusline slot.
--
-- v1 accepts only `Text`, `Row`, `Column`, and `List` subtrees (Plugin API v1
-- Lua Surface RFC, ADR 0009). The statusline composes a single `Row` of `Text`
-- fragments separated by `Text` separators; host layout owns placement and
-- decoration, and there are no global coordinates, shaders, or native
-- windows. Pure and host-free so the encoding is unit testable.

local format = require("statusline.format")

local M = {}

-- Build the statusline `Row` node for an already bounded component list.
function M.row(components, separator)
  local sep = separator or format.SEPARATOR
  local children = {}
  for index, component in ipairs(components) do
    if index > 1 then
      children[#children + 1] = { kind = "Text", text = sep }
    end
    children[#children + 1] = { kind = "Text", text = component }
  end
  return { kind = "Row", children = children }
end

-- Empty statusline placeholder (a `Row` with no fragments).
function M.empty()
  return { kind = "Row", children = {} }
end

return M
