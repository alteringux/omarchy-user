// Kit.Str — tiny stateless string helpers shared by the alteringux.* plugins.
//
//   import "../alteringux.kit" as Kit
//   text: Kit.Str.escapeHtml(raw)        // safe to drop into Text.StyledText
//
// No `.pragma library`: it holds no state, and skipping the pragma lets
// `node --test` require() this file directly (see kit test/str.test.js).

// & < > "  ->  entities, so a string can go inside Text.StyledText / rich text
// without a stray "<" swallowing the rest of the line.
function escapeHtml(s) {
  return String(s === null || s === undefined ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

if (typeof module !== "undefined") {
  module.exports = { escapeHtml: escapeHtml };
}
