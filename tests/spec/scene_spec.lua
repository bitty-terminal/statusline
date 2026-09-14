-- Declarative scene composition unit tests for `statusline.scene`.

local scene = require("statusline.scene")

local function run(context)
  local tap = context.tap

  do
    local empty = scene.empty()
    tap.equal(empty.kind, "Row", "empty is a Row")
    tap.equal(#empty.children, 0, "empty Row has no children")
  end

  do
    local row = scene.row({ "cwd:/c", "title:t" })
    tap.equal(row.kind, "Row", "row is a Row")
    tap.equal(#row.children, 3, "two fragments plus one separator")
    tap.equal(row.children[1].kind, "Text", "fragment is Text")
    tap.equal(row.children[1].text, "cwd:/c", "first fragment text")
    tap.equal(row.children[2].text, " | ", "default separator text")
    tap.equal(row.children[3].text, "title:t", "second fragment text")
  end

  do
    local row = scene.row({ "a", "b" }, " - ")
    tap.equal(row.children[2].text, " - ", "custom separator text")
  end

  do
    local row = scene.row({})
    tap.equal(#row.children, 0, "no components yields no children")
  end
end

return { run = run }
