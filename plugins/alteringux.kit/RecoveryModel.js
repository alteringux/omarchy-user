.pragma library

// Presentation-only records. Dispatchers and arguments are deliberately never
// copied into this model; a selected shortcut is information, not an action.
function keyLabel(binding) {
  var mask = Number(binding.modmask) || 0
  var parts = []
  if (mask & 64) parts.push("Super")
  if (mask & 4) parts.push("Ctrl")
  if (mask & 8) parts.push("Alt")
  if (mask & 1) parts.push("Shift")
  if (mask & 2) parts.push("Caps Lock")
  if (mask & 16) parts.push("Mod2")
  if (mask & 32) parts.push("Mod3")
  if (mask & 128) parts.push("Mod5")
  if (mask & ~255) parts.push("Unknown modifiers " + (mask & ~255))
  var key = String(binding.key || "")
  if (!key && binding.keycode) key = "Keycode " + binding.keycode + " (layout dependent)"
  if (/^code:/i.test(key)) key = "Keycode " + key.slice(5) + " (layout dependent)"
  parts.push(key || "Unknown key")
  return parts.join(" + ")
}

function normalize(bindings) {
  if (!Array.isArray(bindings)) throw new Error("Invalid binding catalog")
  var records = [], seen = {}
  bindings.forEach(function(binding) {
    var description = String(binding.description || "").trim()
    if (!description) return
    var submap = String(binding.submap || "")
    var flags = []
    if (binding.release) flags.push("on release")
    if (binding.repeat) flags.push("repeat while held")
    if (binding.longPress || binding.longpress) flags.push("long press")
    if (binding.mouse) flags.push("mouse binding")
    if (binding.locked) flags.push("available while locked")
    if (binding.inhibit) flags.push("ignores shortcut inhibitor")
    var keys = keyLabel(binding)
    var context = submap ? "Requires submap: " + submap : "Global"
    var identity = JSON.stringify([keys, description, submap, flags])
    if (seen[identity]) return
    seen[identity] = true
    records.push({ id: identity, keys: keys, description: description, source: "global",
      context: context, conditional: !!submap, flags: flags.join(" · "),
      recovery: /\b(reset|restart)\b/i.test(description) })
  })
  return records.sort(function(a, b) {
    return Number(a.conditional) - Number(b.conditional)
      || a.description.localeCompare(b.description) || a.keys.localeCompare(b.keys)
  })
}

// Local documentation is supplied by the shortcut owner, never inferred from
// an emitted signal or a command string. Copy display fields only.
function localRecords(bindings) {
  if (!Array.isArray(bindings)) return []
  var records = [], seen = {}
  bindings.forEach(function(binding) {
    var description = String(binding.description || "").trim()
    var keys = String(binding.keys || "").trim()
    if (!description || !keys) return
    var context = String(binding.context || "Current panel")
    var flags = String(binding.flags || "")
    var id = JSON.stringify(["panel", keys, description, context, flags])
    if (seen[id]) return
    seen[id] = true
    records.push({ id: id, keys: keys, description: description,
      source: String(binding.source || "panel"), context: context,
      conditional: !!binding.conditional, flags: flags,
      recovery: /\b(reset|restart)\b/i.test(description) })
  })
  return records
}

function filter(records, query, recoveryOnly) {
  var needle = String(query || "").toLowerCase().trim()
  return records.filter(function(record) {
    return (!recoveryOnly || record.recovery) && (!needle
      || (record.description + " " + record.keys).toLowerCase().indexOf(needle) >= 0)
  })
}

function filterAudit(collisions, query) {
  var needle = String(query || "").toLowerCase().trim()
  return (Array.isArray(collisions) ? collisions : []).filter(function(record) {
    return !needle || (record.keys + " " + record.description + " "
      + record.classification + " " + record.context).toLowerCase().indexOf(needle) >= 0
  })
}

function auditRecord(binding) {
  var description = String(binding.description || "").trim()
  var submap = String(binding.submap || "")
  var flags = []
  if (binding.release) flags.push("on release")
  if (binding.repeat) flags.push("repeat while held")
  if (binding.longPress || binding.longpress) flags.push("long press")
  if (binding.mouse) flags.push("mouse binding")
  if (binding.locked) flags.push("available while locked")
  if (binding.inhibit) flags.push("ignores shortcut inhibitor")
  var keys = keyLabel(binding)
  return {
    id: JSON.stringify([keys, description, submap, flags]),
    keys: keys,
    description: description,
    source: "global",
    context: submap ? "Requires submap: " + submap : "Global",
    conditional: !!submap,
    flags: flags.join(" · "),
    release: !!binding.release,
    repeat: !!binding.repeat,
    longPress: !!(binding.longPress || binding.longpress),
    mouse: !!binding.mouse,
    locked: !!binding.locked,
    inhibit: !!binding.inhibit,
    key: String(binding.key || ""),
    submap: submap,
    keycode: Number(binding.keycode) || 0,
    modmask: Number(binding.modmask) || 0
  }
}

function chordIdentity(binding) {
  var key = String(binding.key || "")
  var keycode = Number(binding.keycode) || 0
  return JSON.stringify([
    Number(binding.modmask) || 0,
    key,
    keycode,
    String(binding.submap || ""),
    !!binding.mouse
  ])
}

function layerName(mask) {
  var parts = []
  if (mask & 64) parts.push("SUPER")
  if (mask & 4) parts.push("CTRL")
  if (mask & 8) parts.push("ALT")
  if (mask & 1) parts.push("SHIFT")
  if (mask & 2) parts.push("CAPS LOCK")
  if (mask & 16) parts.push("MOD2")
  if (mask & 32) parts.push("MOD3")
  if (mask & 128) parts.push("MOD5")
  if (mask & ~255) parts.push("UNKNOWN:" + (mask & ~255))
  return parts.join("+")
}

function hasExplicitVariant(records) {
  var signatures = {}
  records.forEach(function(record) {
    var signature = [record.release, record.repeat, record.longPress,
      record.locked, record.inhibit].join(":")
    signatures[signature] = true
  })
  return Object.keys(signatures).length > 1
}

function collisionClassification(records) {
  if (records.length === 2 && records[0].release !== records[1].release) return "intentional"
  var descriptions = records.map(function(record) { return record.description })
  var hasReveal = descriptions.some(function(description) {
    return /^Reveal active window on top$/i.test(description)
  })
  var hasFocus = descriptions.some(function(description) {
    return /^Focus on (next|previous) window$/i.test(description)
  })
  if (hasReveal && hasFocus) return "intentional"
  var sameDescription = descriptions.every(function(description) {
    return description === descriptions[0]
  })
  if (sameDescription && hasExplicitVariant(records)) return "intentional"
  return sameDescription ? "unknown" : "actionable"
}

function audit(bindings) {
  if (!Array.isArray(bindings)) throw new Error("Invalid binding catalog")
  var described = bindings.filter(function(binding) {
    return String(binding.description || "").trim().length > 0
  })
  var records = described.map(auditRecord)
  var groups = {}
  described.forEach(function(binding, index) {
    var identity = chordIdentity(binding)
    if (!groups[identity]) groups[identity] = []
    groups[identity].push(records[index])
  })

  var collisions = Object.keys(groups).filter(function(identity) {
    return groups[identity].length > 1
  }).map(function(identity) {
    var recordsForChord = groups[identity]
    var classification = collisionClassification(recordsForChord)
    return {
      id: identity,
      keys: recordsForChord[0].keys,
      description: recordsForChord.map(function(record) { return record.description }).join(" / "),
      context: recordsForChord.map(function(record) { return record.context }).filter(function(value, index, values) {
        return values.indexOf(value) === index
      }).join(" · "),
      flags: recordsForChord.map(function(record) { return record.flags }).filter(Boolean).join(" · "),
      classification: classification,
      records: recordsForChord
    }
  })
  collisions.sort(function(a, b) {
    var rank = { actionable: 0, unknown: 1, intentional: 2 }
    return rank[a.classification] - rank[b.classification] || a.keys.localeCompare(b.keys)
  })

  var layers = {}
  records.forEach(function(record) {
    var mask = record.modmask
    var layer = layerName(mask)
    var key = record.key.toUpperCase()
    if (!layer || !/^[A-Z]$/.test(key)) return
    if (!layers[layer]) layers[layer] = {}
    layers[layer][key] = true
  })
  var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")
  var layerRows = Object.keys(layers).sort().map(function(name) {
    var used = alphabet.filter(function(letter) { return !!layers[name][letter] })
    var unused = alphabet.filter(function(letter) { return !layers[name][letter] })
    return { name: name, used: used, unused: unused, usedCount: used.length, capacity: alphabet.length }
  })

  var actionableCount = collisions.filter(function(row) { return row.classification === "actionable" }).length
  var intentionalCount = collisions.filter(function(row) { return row.classification === "intentional" }).length
  var unknownCount = collisions.filter(function(row) { return row.classification === "unknown" }).length
  return {
    rawCount: bindings.length,
    describedCount: described.length,
    normalizedCount: normalize(bindings).length,
    uniqueChordCount: Object.keys(groups).length,
    collisionCount: collisions.length,
    actionableCount: actionableCount,
    intentionalCount: intentionalCount,
    unknownCount: unknownCount,
    collisions: collisions,
    layers: layerRows,
    usage: {
      mode: "static-only",
      coverage: 0,
      note: "Global binding usage is not instrumented; these metrics describe configured bindings only."
    }
  }
}
