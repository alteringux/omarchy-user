'use strict'

// Native-free fixtures for the presentation model and recovery trigger policy.
// Load the production .js files with only Quickshell's pragma removed; no QML,
// catalog command, recovery executor, or desktop input is available here.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')
const vm = require('node:vm')

const repo = path.resolve(__dirname, '../../../..')
function loadLibrary(relativePath, exportNames) {
  const source = fs.readFileSync(path.join(repo, relativePath), 'utf8')
    .replace(/^\.pragma library\s*/m, '')
  const sandbox = Object.create(null)
  vm.runInNewContext(source, sandbox, { filename: relativePath, timeout: 1000 })
  return Object.fromEntries(exportNames.map(name => [name, sandbox[name]]))
}

const trigger = loadLibrary('plugins/alteringux.kit/RecoveryTrigger.js', [
  'createState', 'dismiss', 'observe', 'attemptWindowMs', 'cooldownMs', 'distinctMissesRequired'
])
const model = loadLibrary('plugins/alteringux.kit/RecoveryModel.js', [
  'keyLabel', 'normalize', 'localRecords', 'filter', 'audit'
])

function miss(chord, pressId, extra = {}) {
  return {
    enabled: true, owned: true, editor: false, composing: false,
    focusLost: false, outcome: 'unhandled', commandModifier: true,
    modifierOnly: false, autoRepeat: false, chord, pressId, context: 'panel-a',
    ...extra
  }
}

function addDistinct(state, prefix, start, step = 100) {
  const reveals = []
  for (let i = 0; i < 3; i++) {
    reveals.push(trigger.observe(state, miss(`${prefix}${i}`, `${prefix}-physical-${i}`), start + i * step))
  }
  return reveals
}

test('trigger reveals on three distinct misses inside four seconds', () => {
  const state = trigger.createState()
  assert.deepEqual(addDistinct(state, 'Ctrl+A', 1000), [false, false, true])
  assert.equal(state.visible, true)
  assert.equal(state.attempts.length, 0)
})

test('window expiry discards old misses and starts a fresh attempt', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'a'), 1000), false)
  assert.equal(trigger.observe(state, miss('Ctrl+B', 'b'), 4999), false)
  assert.equal(trigger.observe(state, miss('Ctrl+C', 'c'), 5000), false)
  assert.equal(state.visible, false)
  assert.equal(state.attempts.length, 1)
})

test('the exact four-second boundary expires the prior window', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'a'), 1000), false)
  assert.equal(trigger.observe(state, miss('Ctrl+B', 'b'), 2000), false)
  assert.equal(trigger.observe(state, miss('Ctrl+C', 'c'), 5000), false)
  assert.equal(state.attempts.length, 1)
})

test('duplicate chord, duplicate physical press, and auto-repeat do not add attempts', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'press-1'), 1000), false)
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'press-2'), 1100), false)
  assert.equal(trigger.observe(state, miss('Ctrl+B', 'press-1'), 1200), false)
  assert.equal(trigger.observe(state, miss('Ctrl+C', 'press-3', { autoRepeat: true }), 1300), false)
  assert.equal(state.attempts.length, 1)
})

test('ordinary typing without a command modifier and modifier-only input are excluded', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('a', 'type-a', { commandModifier: false }), 1000), false)
  assert.equal(trigger.observe(state, miss('Ctrl', 'ctrl-only', { modifierOnly: true }), 1100), false)
  assert.equal(state.attempts.length, 0)
})

test('explicit typing classification is excluded even when metadata has a command modifier', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'typed-press', { typing: true }), 1000), false)
  assert.equal(state.attempts.length, 0)
})

test('editor, composition, unowned, disabled, and lost-focus inputs clear and do not count', () => {
  for (const excluded of [
    { editor: true }, { composing: true }, { owned: false }, { enabled: false }, { focusLost: true }
  ]) {
    const state = trigger.createState()
    assert.equal(trigger.observe(state, miss('Ctrl+A', 'seed'), 1000), false)
    assert.equal(trigger.observe(state, miss('Ctrl+B', 'excluded', excluded), 1100), false)
    assert.equal(state.attempts.length, 0)
  }
})

test('handled and matched-but-unavailable outcomes clear the attempt streak', () => {
  for (const outcome of ['handled', 'unavailable']) {
    const state = trigger.createState()
    assert.equal(trigger.observe(state, miss('Ctrl+A', 'seed'), 1000), false)
    assert.equal(trigger.observe(state, miss('Ctrl+B', 'matched', { outcome }), 1100), false)
    assert.equal(state.attempts.length, 0)
  }
})

test('context changes clear old attempts before the new context event is counted', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'a', { context: 'panel-a' }), 1000), false)
  assert.equal(trigger.observe(state, miss('Ctrl+B', 'b', { context: 'panel-b' }), 1100), false)
  assert.deepEqual(Array.from(state.attempts, item => item.chord), ['Ctrl+B'])
})

test('dismissal clears the streak and enforces the 30-second cooldown boundary', () => {
  const state = trigger.createState()
  assert.deepEqual(addDistinct(state, 'Ctrl+', 1000), [false, false, true])
  trigger.dismiss(state, 1300)
  assert.equal(state.visible, false)
  assert.equal(state.attempts.length, 0)
  assert.equal(trigger.observe(state, miss('Ctrl+D', 'd'), 31299), false)
  assert.equal(state.attempts.length, 0)
  assert.equal(trigger.observe(state, miss('Ctrl+E', 'e'), 31300), false)
  assert.equal(state.attempts.length, 1)
})

test('clock rollback clears attempts and cannot reveal from the regressed event', () => {
  const state = trigger.createState()
  assert.equal(trigger.observe(state, miss('Ctrl+A', 'a'), 5000), false)
  assert.equal(trigger.observe(state, miss('Ctrl+B', 'b'), 4000), false)
  assert.equal(state.attempts.length, 0)
  assert.equal(trigger.observe(state, miss('Ctrl+C', 'c'), 4500), false)
  assert.equal(state.attempts.length, 0)
})

test('catalog recovery matching uses case-insensitive whole words in descriptions only', () => {
  const records = model.normalize([
    { description: 'Reset zoom', key: 'Z', modmask: 4 },
    { description: 'RESTART shell', key: 'R', modmask: 64 },
    { description: 'reset-session', key: 'S', modmask: 8 },
    { description: 'preset', key: 'P', modmask: 4 },
    { description: '', key: 'D', command: 'restart now' },
    { description: 'Open preferences', key: 'O', command: 'restart now' }
  ])
  assert.deepEqual(Array.from(records.filter(row => row.recovery), row => row.description), [
    'Reset zoom', 'reset-session', 'RESTART shell'
  ])
  assert.equal(records.some(row => row.description === 'preset' && row.recovery), false)
  assert.equal(records.some(row => row.description === 'Open preferences' && row.recovery), false)
})

test('catalog removes exact duplicates but keeps same descriptions on different chords', () => {
  const duplicate = { description: 'Reset zoom', key: 'Z', modmask: 4 }
  const records = model.normalize([duplicate, { ...duplicate }, { ...duplicate, key: 'X' }])
  assert.equal(records.length, 2)
  assert.equal(records.filter(row => row.description === 'Reset zoom').length, 2)
})

test('key labels retain modifier, keycode, submap, release, repeat, and long-press facts', () => {
  const records = model.normalize([
    { description: 'Restart shell', key: 'code:42', modmask: 76, submap: 'resize', release: true, repeat: true, longPress: true }
  ])
  assert.equal(records.length, 1)
  assert.equal(records[0].keys, 'Super + Ctrl + Alt + Keycode 42 (layout dependent)')
  assert.equal(records[0].context, 'Requires submap: resize')
  assert.equal(records[0].conditional, true)
  assert.match(records[0].flags, /on release/)
  assert.match(records[0].flags, /repeat while held/)
  assert.match(records[0].flags, /long press/)
  assert.equal(model.keyLabel({ keycode: 31, modmask: 4 }), 'Ctrl + Keycode 31 (layout dependent)')
})

test('local records dedupe and recovery search covers descriptions and displayed keys', () => {
  const local = model.localRecords([
    { keys: 'Ctrl+R', description: 'Restart timer', source: 'alteringux.timers', context: 'Current panel' },
    { keys: 'Ctrl+R', description: 'Restart timer', source: 'alteringux.timers', context: 'Current panel' },
    { keys: 'Ctrl+Shift+X', description: 'Reset timer', source: 'alteringux.timers' }
  ])
  assert.equal(local.length, 2)
  assert.deepEqual(Array.from(model.filter(local, 'CTRL+R', true), row => row.description), ['Restart timer'])
  assert.equal(model.filter(local, '', true).length, 2)
  assert.equal(model.filter(local, 'missing', true).length, 0)
})

test('audit preserves collision evidence before presentation deduplication', () => {
  const result = model.audit([
    { modmask: 64, key: 'A', description: 'First action', dispatcher: '__lua', arg: 'secret' },
    { modmask: 64, key: 'A', description: 'Second action', dispatcher: '__lua', arg: 'other-secret' },
    { modmask: 0, key: 'F9', description: 'Start dictation', release: false },
    { modmask: 0, key: 'F9', description: 'Stop dictation', release: true },
    { modmask: 8, key: 'TAB', description: 'Focus on next window' },
    { modmask: 8, key: 'TAB', description: 'Reveal active window on top' }
  ])

  assert.deepEqual({
    rawCount: result.rawCount,
    describedCount: result.describedCount,
    normalizedCount: result.normalizedCount,
    uniqueChordCount: result.uniqueChordCount,
    collisionCount: result.collisionCount,
    actionableCount: result.actionableCount,
    intentionalCount: result.intentionalCount,
    unknownCount: result.unknownCount
  }, {
    rawCount: 6,
    describedCount: 6,
    normalizedCount: 6,
    uniqueChordCount: 3,
    collisionCount: 3,
    actionableCount: 1,
    intentionalCount: 2,
    unknownCount: 0
  })

  assert.equal(result.collisions[0].classification, 'actionable')
  assert.equal(result.collisions[0].records.length, 2)
  assert.equal('dispatcher' in result.collisions[0].records[0], false)
  assert.equal('arg' in result.collisions[0].records[0], false)
})

test('audit reports modifier-layer capacity without confusing it with usage', () => {
  const result = model.audit([
    { modmask: 64, key: 'A', description: 'Super A' },
    { modmask: 72, key: 'B', description: 'Super Alt B' },
    { modmask: 68, key: 'C', description: 'Super Ctrl C' },
    { modmask: 1, key: 'D', description: 'Shift D' }
  ])
  const superLayer = result.layers.find(row => row.name === 'SUPER')
  const altLayer = result.layers.find(row => row.name === 'SUPER+ALT')

  assert.deepEqual(Array.from(superLayer.used), ['A'])
  assert.equal(superLayer.usedCount, 1)
  assert.equal(superLayer.unused.includes('B'), true)
  assert.equal(altLayer.used[0], 'B')
  assert.equal(result.usage.coverage, 0)
  assert.equal(result.usage.mode, 'static-only')
})

test('audit keeps exact duplicate evidence separate from its deduplicated presentation', () => {
  const duplicate = { modmask: 64, key: 'A', description: 'Open dashboard' }
  const result = model.audit([duplicate, { ...duplicate }])

  assert.equal(result.normalizedCount, 1)
  assert.equal(result.collisionCount, 1)
  assert.equal(result.unknownCount, 1)
  assert.equal(result.collisions[0].classification, 'unknown')
  assert.equal(result.collisions[0].records.length, 2)
})

test('audit preserves flagged variants and separates submaps and mouse chords', () => {
  const result = model.audit([
    { modmask: 64, key: 'R', description: 'Resize window', repeat: true },
    { modmask: 64, key: 'R', description: 'Resize window', longPress: true },
    { modmask: 64, key: 'R', description: 'Resize window', submap: 'resize' },
    { modmask: 64, key: 'R', description: 'Resize window', mouse: true }
  ])

  assert.equal(result.collisionCount, 1)
  assert.equal(result.intentionalCount, 1)
  assert.equal(result.collisions[0].classification, 'intentional')
  assert.match(result.collisions[0].records[0].flags, /repeat while held/)
  assert.match(result.collisions[0].records[1].flags, /long press/)
  assert.equal(result.uniqueChordCount, 3)
})

test('audit keeps all modifier bits in deterministic layer names', () => {
  const result = model.audit([{
    modmask: 64 | 4 | 8 | 1 | 2 | 16 | 32 | 128,
    key: 'Z',
    description: 'Full modifier chord'
  }])

  assert.deepEqual(Array.from(result.layers, row => row.name), [
    'SUPER+CTRL+ALT+SHIFT+CAPS LOCK+MOD2+MOD3+MOD5'
  ])
  assert.deepEqual(Array.from(result.layers[0].used), ['Z'])
  assert.equal(model.keyLabel({ modmask: 64 | 512, key: 'A' }),
    'Super + Unknown modifiers 512 + A')
})

test('presentation records omit command and executor fields; invalid catalogs reject', () => {
  const records = model.normalize([{
    description: 'Reset panel', key: 'K', modmask: 4,
    command: 'must not be copied', args: ['must not be copied'], dispatcher: 'must not be copied'
  }])
  assert.deepEqual(Object.keys(records[0]).sort(), [
    'conditional', 'context', 'description', 'flags', 'id', 'keys', 'recovery', 'source'
  ])
  assert.equal('command' in records[0], false)
  assert.equal('args' in records[0], false)
  assert.throws(() => model.normalize('{"not":"an array"}'), /Invalid binding catalog/)
})

test('trigger stores only ephemeral attempt metadata and calls no executor', () => {
  const state = trigger.createState()
  const event = miss('Ctrl+A', 'physical-a', { command: 'inert fixture only', args: ['inert'] })
  assert.equal(trigger.observe(state, event, 1000), false)
  assert.deepEqual(Object.keys(state.attempts[0]).sort(), ['chord', 'pressId', 'time'])
  assert.equal('command' in state.attempts[0], false)
  assert.equal('args' in state.attempts[0], false)
})
