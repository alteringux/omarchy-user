const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

// ponytail: direct QML references only; add parsing if generated bindings need coverage.
const invalidReferences = []
function checkPaletteInstances(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name)
    if (entry.isDirectory() && entry.name !== "test") checkPaletteInstances(file)
    else if (entry.isFile() && entry.name.endsWith(".qml")) {
      fs.readFileSync(file, "utf8").split("\n").forEach((line, index) => {
        if (!line.trimStart().startsWith("//") && /\bKit\.Palette\.[a-z]\w*/.test(line)) {
          invalidReferences.push(`${path.relative(path.join(__dirname, "../.."), file)}:${index + 1}`)
        }
      })
    }
  }
}
for (const entry of fs.readdirSync(path.join(__dirname, "../.."), { withFileTypes: true })) {
  if (entry.isDirectory() && entry.name.startsWith("alteringux.")) {
    checkPaletteInstances(path.join(__dirname, "../..", entry.name))
  }
}
assert.deepEqual(invalidReferences, [], "Palette roles belong to an instance; Palette is not a singleton")

const source = fs.readFileSync(path.join(__dirname, "..", "PaletteLogic.js"), "utf8")
const logic = {}
vm.runInNewContext(source.replace(/^\.pragma library\s*/, ""), logic)

const channelBytes = [0, 51, 102, 153, 204, 255]
for (let byte = 0; byte < 256; byte++) {
  const value = byte / 255
  const color = logic.webSafeColor({ r: value, g: value, b: value, a: 1 })
  const channels = [3, 5, 7].map((offset) => parseInt(color.slice(offset, offset + 2), 16))
  assert.ok(channels.every((channel) => channel === channels[0] && channelBytes.includes(channel)))
}

const black = { r: 0, g: 0, b: 0, a: 1 }
const nearBlackBlue = { r: 0, g: 0, b: 0.2, a: 1 }
const first = logic.contrastColorFor(black, nearBlackBlue, 1.047703, black)
const stricter = logic.contrastColorFor(black, nearBlackBlue, 1.047903, black)
const parseHex = (hex) => ({
  r: parseInt(hex.slice(3, 5), 16) / 255,
  g: parseInt(hex.slice(5, 7), 16) / 255,
  b: parseInt(hex.slice(7, 9), 16) / 255,
  a: 1,
})
assert.ok(logic.contrastRatio(parseHex(first), nearBlackBlue) < 1.047903)
assert.ok(logic.contrastRatio(parseHex(stricter), nearBlackBlue) >= 1.047903)
assert.equal(logic.contrastRatio({ r: 0, g: 0, b: 0, a: 0 }, { r: 1, g: 1, b: 1, a: 1 }), 1)

const safeForeground = logic.contrastColorFor(
  { r: 0.8, g: 0.8, b: 0.8, a: 1 },
  { r: 0, g: 0, b: 0, a: 0.05 },
  1.5,
  { r: 1, g: 1, b: 1, a: 1 },
)
assert.ok(logic.contrastRatio(parseHex(safeForeground),
  { r: 0, g: 0, b: 0, a: 0.05 }, { r: 1, g: 1, b: 1, a: 1 }) >= 1.5)

for (const [surface, backdrop] of [
  [{ r: 0.29, g: 0.29, b: 0.29, a: 1 }, black],
  [{ r: 0, g: 0, b: 0, a: 0.1 }, { r: 0, g: 0, b: 0, a: 0.1 }],
]) {
  const foreground = parseHex(logic.contrastColorFor(
    { r: 0.6, g: 0.6, b: 0.6, a: 1 }, surface, 4.5, backdrop,
  ))
  assert.ok([foreground.r, foreground.g, foreground.b]
    .every((channel) => channelBytes.includes(Math.round(channel * 255))))
  assert.ok(logic.contrastRatio(foreground, surface, backdrop) >= 4.5)
}
