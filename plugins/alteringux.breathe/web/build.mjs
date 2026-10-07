import fs from 'node:fs'
import path from 'node:path'
import assert from 'node:assert/strict'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const plugin = path.resolve(here, '..')
const dist = path.join(here, 'dist')
const model = await import(pathToFileURL(path.join(plugin, 'Model.js')))
const canonical = JSON.parse(fs.readFileSync(path.join(plugin, 'techniques.json'), 'utf8'))
const modelTechniques = model.default?.TECHNIQUES ?? model.TECHNIQUES
assert.deepStrictEqual(modelTechniques, canonical.techniques, 'Model.js catalogue does not match techniques.json')
fs.rmSync(dist, { recursive: true, force: true })
fs.mkdirSync(dist, { recursive: true })
for (const name of ['index.html', 'app.js', 'styles.css', 'model-bridge.js']) {
  fs.copyFileSync(path.join(here, name), path.join(dist, name))
}
fs.copyFileSync(path.join(plugin, 'Model.js'), path.join(dist, 'model.js'))
console.log(`Built ${dist} with ${modelTechniques.length} techniques`)

