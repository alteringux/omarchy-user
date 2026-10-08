import test from "node:test"
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { accessSync, constants, lstatSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const installer = resolve(import.meta.dirname, "../install.py")

test("installer help is side-effect free and package install works in an isolated config", () => {
  const scratch = mkdtempSync(join(tmpdir(), "agentglass-omarchy-install-"))
  try {
    const config = join(scratch, "omarchy")
    const bin = join(scratch, "bin")
    mkdirSync(bin)
    const oldCli = join(scratch, "old-agentglass-agent")
    writeFileSync(oldCli, "old Agentglass CLI")
    symlinkSync(oldCli, join(bin, "agentglass-agent"))
    const plugins = join(config, "plugins")
    mkdirSync(join(plugins, "alteringux.kit"), { recursive: true })
    writeFileSync(join(config, "shell.json"), JSON.stringify({ bar: { layout: { right: [{ id: "omarchy.agents" }] } } }))

    const help = spawnSync("python3", [installer, "--help"], { encoding: "utf8", env: { ...process.env, XDG_CONFIG_HOME: scratch } })
    assert.equal(help.status, 0, help.stderr)
    assert.match(help.stdout, /--omarchy-dir/)
    assert.match(help.stdout, /--bin-dir/)
    assert.equal(readlinkSync(join(bin, "agentglass-agent")), oldCli)
    assert.deepEqual(readdirSync(config).sort(), ["plugins", "shell.json"])

    const installed = spawnSync("python3", [installer, "--omarchy-dir", config, "--bin-dir", bin], { encoding: "utf8" })
    assert.equal(installed.status, 0, installed.stderr)
    const plugin = join(plugins, "alteringux.agentglass")
    assert.equal(readFileSync(join(plugin, "manifest.json"), "utf8").length > 0, true)
    assert.equal(readFileSync(join(plugin, "bin", "agentglass-agent"), "utf8").startsWith("#!/usr/bin/env python3"), true)
    assert.equal(readFileSync(join(bin, "agentglass-agent"), "utf8").startsWith("#!/usr/bin/env python3"), true)
    accessSync(join(bin, "agentglass-agent"), constants.X_OK)
    const cliBackup = readdirSync(bin).find((name) => name.startsWith("agentglass-agent.bak.agentglass."))
    assert.ok(cliBackup)
    assert.equal(lstatSync(join(bin, cliBackup)).isSymbolicLink(), true)
    assert.equal(readlinkSync(join(bin, cliBackup)), oldCli)
    const shell = JSON.parse(readFileSync(join(config, "shell.json"), "utf8"))
    assert.deepEqual(shell.plugins, [{ id: "alteringux.agentglass" }])
    assert.equal(shell.bar.layout.right[1].id, "alteringux.agentglass")
    assert.equal(readdirSync(config).filter((name) => name.startsWith("shell.json.bak.agentglass.")).length, 1)
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
})
