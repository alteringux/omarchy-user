# Omarchy plugin suite: product and design teardown

Date: 2026-10-08. Scope: 42 first-party `alteringux.*` product-plugin manifests
in this machine's checkout. `alteringux.kit` is shared infrastructure, not a
product plugin. The two `io.github.*` packages are third-party and excluded.

This teardown uses the current manifests, package QML entry points, the shared
Kit/ADR decisions, the existing package source audit, and one read-only capture
of the current desktop. The capture shows the real widget strip, but the active
workspace is dominated by terminal windows; it is not rendered evidence for
each plugin. Per-package visual behavior, broad native keyboard journeys,
AT-SPI export and enlarged-text layouts remain unverified where the existing
ledger says so. Product positioning below is an inference from the local
product descriptions and source surfaces, not market research or measured
usage.

## 1. Product snapshot

This is a personal desktop control plane built as native Omarchy/Quickshell
plugins. Its promise is to put useful state, small actions and longer workflows
one interaction away from the desktop, with local scripts and shared QML
components doing the work behind the shell surfaces. It is best understood as
a curated personal environment, not a general plugin marketplace.

## 2. Users and jobs

- **Machine owner:** check machine, network, market, time and task state without
  opening a separate app.
- **Builder/operator:** launch, monitor and review local AI, coding, media and
  automation workflows from native surfaces.
- **Learner/reader:** run small focus, memory, language and breathing sessions
  with progress kept locally.

The recurring job is “notice a relevant state, take the smallest useful action,
return to the current task.” Some packages instead support an intentional
session (Breathe, Recall, Glimpse, Wordstep), where a takeover or fullscreen
surface is part of the job rather than incidental chrome.

## 3. Product loop

**Trigger:** a glance at a bar, a notification, a selected text passage, or an
intentional hotkey. **Action:** inspect a compact state or open a package panel.
**Reward:** a verified action, a timely reminder, a useful answer, or progress
in a chosen practice. **Return:** state persists locally or the bar reflects
the next meaningful change. Pulse is the suite-level attention loop; the rest
of the suite supplies domain-specific triggers and actions.

Acquisition is owner-installed configuration, not a public growth funnel.
Activation is the first useful bar glance or completed local workflow. Retention
comes from recurrence and saved state. There is no demonstrated network effect.

## 4. Architecture and UX system

The suite combines persistent bar summaries, anchored panels, dedicated overlays,
headless services, and local CLI/data engines. `alteringux.kit` shares theme,
typography, overflow, panel, keyboard, action and recovery behavior. The product
choice that works best is progressive disclosure: glanceable bar, then a focused
panel or purpose-built session. A second bar handles overflow; the panel owner
keeps the original widget's behavior and popup routing.

Core entities vary by domain: events, sessions, tasks, jobs, readings, messages,
matches, prices, repos, timers and selected text. The system is coherent when
these remain domain-specific while navigation, state feedback and shell chrome
remain shared.

## 5. Design language and craft signals

1. **Glance then drill down:** bar widgets expose the smallest useful state;
   panels retain detail and actions.
2. **Native surfaces:** anchored panels and overlays feel part of the shell and
   preserve current-work context.
3. **Thin views, local engines:** several widgets watch JSON produced by local
   commands rather than repeating domain logic in QML.
4. **Shared readable chrome:** semantic theme roles, scaled type, stable
   overflow readers and Kit panel structures are reusable quality signals.
5. **Intentional intensity:** fullscreen practice or deadline interventions
   are only defensible when users can understand, configure and leave them.

These patterns distinguish the suite from a folder of unrelated desktop
gadgets, but the same consistency increases the cost of shared Kit regressions.

## 6. Value and UX quality

Time to value is seconds for passive widgets and one deliberate open/action for
panels; onboarding varies by package and is not measured. Information density is
high by design. The desktop capture confirms many compact signals can coexist,
but also shows the bar is already a crowded surface. Delight comes from
context-aware state and native actions. Trust comes from local state, explicit
settings and visible action status; it is weakened wherever work is detached,
AI/network-backed, or screen/microphone access is not obvious. The largest
system-level struggle is not a missing shared style token: it is the lack of
current rendered review for every visible package and display condition.

## 7. Business model

No revenue model or paid/free boundary is present in the repository. This is a
personal local configuration, so monetization would be an unsupported
assumption and should not shape this fix batch.

## 8. Competitive landscape

Directional comparison (inferred from public product descriptions; not a
feature-by-feature benchmark):

| Alternative | Strength | Suite advantage | Tradeoff |
|---|---|---|---|
| KDE Plasma widgets | Integrated desktop widgets and broad user customization | More opinionated workflows, local engines and cross-plugin attention | Less general-purpose placement and user composition |
| GNOME Shell Extensions | Extensions can change panel and broader shell behavior | Deliberate Omarchy-specific workflow composition | Smaller ecosystem and owner-only maintenance |
| Rainmeter | User-composable desktop skins, including system and media controls | Native shell anchoring and deeper local workflow integration | Fewer independently rearrangeable surfaces |
| Übersicht | HTML/JS desktop widgets displaying command output | Native Quickshell controls, panels and keyboard ownership | Less portable across desktop platforms |

The suite wins when the user values one integrated, locally tuned environment;
the alternatives win on wider distribution, generality or independent
composition. Official references: [Plasma Handbook](https://docs.kde.org/stable_kf6/en/plasma-desktop/plasma-desktop/plasma-desktop.pdf),
[GNOME Shell Extensions](https://extensions.gnome.org/about/),
[Rainmeter manual](https://docs.rainmeter.net/manual/),
[Übersicht](https://tracesof.net/uebersicht/).

## 9. Growth strategy

There is no evidence of an external acquisition loop. The likely internal loop
is owner need → small plugin → shared Kit adoption → reusable behavior. Horizontal
expansion adds a new desktop job; vertical expansion deepens an existing
workflow; platform expansion improves the Kit/CLI contracts. The constraint is
maintainer attention: every new surface adds review and runtime-support cost.

## 10. AI and future readiness

AI is assistive/embedded in selected packages (Ask, Calendar rescheduling,
Deskpet vision/chat, Phone, Flow, Newsbar recipe generation, and local coding
agent surfaces). It should remain an explicit capability with clear data
boundaries and observable completion. Agentifying deterministic sampling,
refresh and summarization is plausible; autonomous desktop action is a poor
default because this product has privileged local context and a single owner.

## 11. Useful product metrics

No telemetry contract is established for this suite, so these are proposed
local-only measures, not current facts:

- **North star:** completed useful actions per active plugin-week, counted
  locally and without raw content.
- **Inputs:** first successful action after install; repeat completion of
  deliberate sessions; attention items resolved before stale.
- **Guardrail:** avoid unwanted interruptions and accidental actions.
- **Blind spot:** uninstalled/unused plugins and their maintenance cost are not
  captured by visible activity alone.

## 12. Friction and weaknesses

- 42 products create bar density and discoverability pressure; bottom-bar
  overflow helps, but configuration and first-run curation remain important.
- Scope and intensity differ sharply: a quiet status pill, an interruptive
  deadline takeover and a fullscreen training exercise need different consent
  and exit affordances.
- Broad rendered review is still open; source scans and QML compilation do not
  establish layout quality, real focus order or screen-reader output.
- Native AT-SPI export and many package-specific keyboard/action journeys remain
  unverified. These are evidence gaps, not blanket proof of broken controls.
- Some packages depend on network APIs, audio, microphone, AI services or
  compositor-specific surfaces; their trust and failure states need package
  level review.

## 13. Risk matrix

| Risk | Category | Severity / likelihood | Mitigation |
|---|---|---|---|
| Shared Kit regression affects many packages | Technical | High / medium | Scoped Kit checks plus representative and package-level loading evidence |
| Crowded bars obscure meaningful state | UX | Medium / high | Keep bar entries glanceable; make overflow and placement intentional |
| Intrusive or AI-enabled behavior surprises the owner | Trust | High / medium | Explicit opt-in, readable state, predictable dismissal and clear local/network boundaries |
| Source pass is mistaken for visual/runtime completion | Delivery | High / high | Track evidence per package and surface; do not promote unverified status |

## 14. Opportunities and redesign ideas

1. Finish rendered review of the visible surfaces using the standards already
   present; turn only confirmed defects into package fixes.
2. Surface a concise “what this plugin does / why it is here” first-run map from
   current manifests and preserve the shared Kit distinction.
3. Keep attention based on verified actions and explicit urgency, not activity
   volume.

**Strategic bet:** make the suite a coherent personal control plane whose
plugins can be understood and safely maintained, rather than maximize plugin
count. **Moonshot:** a local intent layer that can answer “what needs my
attention?” from existing plugin state without sending raw personal data away.

## 15. Verdict

The suite's strength is the combination of persistent glanceable state, focused
native workflows and local engines under one shell. Its break point is
operational complexity: many packages, a crowded desktop, uneven evidence and
high Kit blast radius. The durable advantage is the owner's integrated local
workflow and shared shell-native interaction model; it is not a moat against
distributed desktop-widget ecosystems.

## Per-plugin design choices

Each row links the package manifest and its primary visible or service entry point; the links make the design choice traceable to current source. These are entry points, not proof that every state was rendered. The choice and judgment columns use manifest purpose and package surface names;
judgments are design analysis, not proof that every runtime state was rendered.

| Plugin | Chosen product/design shape | Teardown judgment and fix direction | Source entry points |
|---|---|---|---|
| `agenda` | Headless calendar watcher that sends event reminders; Calendar remains the editor/source. | Good separation of authoring from timely notification. Keep one event source; verify stale/error feedback and reminder timing.  [manifest.json](../../plugins/alteringux.agenda/manifest.json) · [Service.qml](../../plugins/alteringux.agenda/Service.qml) · [Model.js](../../plugins/alteringux.agenda/Model.js) |
| `agentglass` | Native bar overview and panel for local coding-agent workflows. | High-value, context-rich glance. Fixed: the installer now resolves its CLI beside the packaged plugin, so it works in this in-place distribution. Keep status hierarchy compact and action ownership clear in long output.  [manifest.json](../../plugins/alteringux.agentglass/manifest.json) · [BarWidget.qml](../../plugins/alteringux.agentglass/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.agentglass/Panel.qml) |
| `ask` | Prompt → NanoGPT answer → optional Piper speech. | Fast answer loop with useful multimodal output. Keep model/provider and speech state explicit; preserve answer text when speech fails.  [manifest.json](../../plugins/alteringux.ask/manifest.json) · [Prompt.qml](../../plugins/alteringux.ask/Prompt.qml) |
| `bottombar` | Second persistent bar instantiating the actual overflow widgets. | Strong reuse and continuity. Treat available space and widget ownership as layout constraints; do not let it become a second noisy primary bar.  [manifest.json](../../plugins/alteringux.bottombar/manifest.json) · [BottomBar.qml](../../plugins/alteringux.bottombar/BottomBar.qml) |
| `breathe` | Catalog, compact guided session, fullscreen guide, custom patterns and practice metrics. | Correctly separates choosing from doing. Fullscreen is appropriate for guided attention; controls and exit need to remain obvious.  [manifest.json](../../plugins/alteringux.breathe/manifest.json) · [BarWidget.qml](../../plugins/alteringux.breathe/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.breathe/Panel.qml) · [Guide.qml](../../plugins/alteringux.breathe/Guide.qml) |
| `calendar` | Month grid for browsing/time blocking, with event authoring and assistant rescheduling. | Good calendar-first mental model. The assistant can execute add/move/remove requests, not only suggest them; fixed the missing before-submit disclosure and directs users to review its result. Keep month navigation distinct from day editing and from Agenda's reminder role.  [manifest.json](../../plugins/alteringux.calendar/manifest.json) · [BarWidget.qml](../../plugins/alteringux.calendar/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.calendar/Panel.qml) |
| `cliamp` | Bottom-bar transport and live spectrum, with a richer control panel. | Good match to continuous media state. Spectrum is decorative support; transport remains the primary action and must remain reachable.  [manifest.json](../../plugins/alteringux.cliamp/manifest.json) · [BarWidget.qml](../../plugins/alteringux.cliamp/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.cliamp/Panel.qml) |
| `clock` | Bar date/time readout opens a month calendar; today is a hero and month/year navigation does not select days. | A useful reinterpretation of a clock click. Shared visible Help was missing despite F1 hints; now added while keeping the date-grid design.  [manifest.json](../../plugins/alteringux.clock/manifest.json) · [BarWidget.qml](../../plugins/alteringux.clock/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.clock/Panel.qml) |
| `conductor` | Ritual runner and single-pane status cockpit across plugins. | Suite orchestration has a clear “one run” promise. Keep step order, current step, failure and retry visually distinct.  [manifest.json](../../plugins/alteringux.conductor/manifest.json) · [BarWidget.qml](../../plugins/alteringux.conductor/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.conductor/Panel.qml) |
| `countdown` | Event-oriented days-remaining bar marquee plus list/editor panel. | Strong glance-to-manage loop. Make dates and labels complete and keep expiry/empty states calm.  [manifest.json](../../plugins/alteringux.countdown/manifest.json) · [BarWidget.qml](../../plugins/alteringux.countdown/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.countdown/Panel.qml) |
| `cpumon` | CPU-focused bar summary and detailed per-core/process panel using shared sampler. | Focused drill-down avoids forcing a full system dashboard into one popup. Keep units and sample freshness visible.  [manifest.json](../../plugins/alteringux.cpumon/manifest.json) · [BarWidget.qml](../../plugins/alteringux.cpumon/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.cpumon/Panel.qml) |
| `cursortrail` | Ambient, click-through fading pointer effect. | Minimal interaction is the product. Preserve click-through and make intensity/disable controls discoverable without adding UI noise.  [manifest.json](../../plugins/alteringux.cursortrail/manifest.json) · [BarWidget.qml](../../plugins/alteringux.cursortrail/BarWidget.qml) |
| `dashboard` | News, machine status and CLI-pushed notes in an overlay. | Convenient daily brief, but three content jobs can compete. News already showed its age; the system heading now does too, and an empty snapshot no longer claims “Up to date.” Preserve clear sections and source/age context; do not flatten notes into news.  [manifest.json](../../plugins/alteringux.dashboard/manifest.json) · [BarWidget.qml](../../plugins/alteringux.dashboard/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.dashboard/Panel.qml) |
| `deskpet` | Persistent companion overlay with direct pet actions, settings, optional vision AI and chattiness. | Emotional delight is distinct from utility. Unsolicited speech and screen vision need clear opt-in and quiet controls.  [manifest.json](../../plugins/alteringux.deskpet/manifest.json) · [BarWidget.qml](../../plugins/alteringux.deskpet/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.deskpet/Panel.qml) |
| `devcast` | Turn local coding session transcripts into a scrub/play replay and export. | Strong artifact-centered workflow. Keep replay provenance and generated media actions distinct from the live agent.  [manifest.json](../../plugins/alteringux.devcast/manifest.json) · [BarWidget.qml](../../plugins/alteringux.devcast/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.devcast/Panel.qml) |
| `dictionary` | Search/highlight launcher, suggestion list, then a full word overview. | Good progressive disclosure. Preserve selected-text context and a fast return path from detail to suggestions.  [manifest.json](../../plugins/alteringux.dictionary/manifest.json) · [Dictionary.qml](../../plugins/alteringux.dictionary/Dictionary.qml) |
| `diskmon` | Bar gauge plus mount, trend and large-directory diagnostics. | Good “notice then explain” model. Keep watched path and stale/error state visible; avoid treating all mounts as equally urgent.  [manifest.json](../../plugins/alteringux.diskmon/manifest.json) · [BarWidget.qml](../../plugins/alteringux.diskmon/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.diskmon/Panel.qml) |
| `flow` | Bar summary of latest flow output, with editable/re-runnable node canvas. | Good split between outcome and construction. Protect output readability and make unsaved edits/running state obvious.  [manifest.json](../../plugins/alteringux.flow/manifest.json) · [BarWidget.qml](../../plugins/alteringux.flow/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.flow/Panel.qml) |
| `glimpse` | Photo-memory exercise with timed reveal, adaptive drills and scheduled recall. | Session loop fits the training job. Clearly distinguish study from quiz and explain image/network availability.  [manifest.json](../../plugins/alteringux.glimpse/manifest.json) · [BarWidget.qml](../../plugins/alteringux.glimpse/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.glimpse/Panel.qml) · [Overlay.qml](../../plugins/alteringux.glimpse/Overlay.qml) |
| `grip` | Aging task counter, recurring check-in and escalated fullscreen deadline intervention. | Escalation may help accountability but risks coercive interruption. Keep escalation configurable, dismissible and transparent.  [manifest.json](../../plugins/alteringux.grip/manifest.json) · [BarWidget.qml](../../plugins/alteringux.grip/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.grip/Panel.qml) · [Prompt.qml](../../plugins/alteringux.grip/Prompt.qml) |
| `memmon` | Memory pressure glance with swap, trend and process drill-down. | Useful specialist view paired with shared sampler. Emphasize pressure and available memory rather than raw totals alone.  [manifest.json](../../plugins/alteringux.memmon/manifest.json) · [BarWidget.qml](../../plugins/alteringux.memmon/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.memmon/Panel.qml) |
| `nanogpt` | Provider usage/quota dashboard with daily/model breakdown and model detail. | Usage-first analytics are actionable. The collector already stored `updatedAt` while the UI hid it; the panel now shows the successful snapshot time and refresh-in-progress state, so retained data can be judged by age. Keep quota period and provider clear.  [manifest.json](../../plugins/alteringux.nanogpt/manifest.json) · [BarWidget.qml](../../plugins/alteringux.nanogpt/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.nanogpt/Panel.qml) |
| `netwatch` | Live transfer-rate glance plus time rollups, quota alerts and connection breakdown. | Good layering of rate → history → current connections. Avoid conflating local interface totals with per-process attribution.  [manifest.json](../../plugins/alteringux.netwatch/manifest.json) · [BarWidget.qml](../../plugins/alteringux.netwatch/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.netwatch/Panel.qml) |
| `newsbar` | Persistent dual feed: world headlines and configurable story source; click reads story aloud. | Distinct editorial modes are useful but compete for a second bar. Source review found the refresh glyph was mouse-only; fixed with a named, keyboard-focusable `Kit.ActionButton`, preserving the busy spinner and refresh action. Keep source switcher, read/stop state and story provenance explicit.  [manifest.json](../../plugins/alteringux.newsbar/manifest.json) · [NewsBar.qml](../../plugins/alteringux.newsbar/NewsBar.qml) |
| `notifications` | Daemon, toast, DND and searchable history. | Correctly separates passive arrival from deliberate history. Preserve focus/input ownership and make DND state legible.  [manifest.json](../../plugins/alteringux.notifications/manifest.json) · [Service.qml](../../plugins/alteringux.notifications/Service.qml) |
| `phone` | Contact picker enters live voice conversation with memory/tools and optional inbound calls. | High-value hands-free interaction, high trust cost. Make recording/input, opt-in inbound calls, active tools and call termination unmistakable.  [manifest.json](../../plugins/alteringux.phone/manifest.json) · [BarWidget.qml](../../plugins/alteringux.phone/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.phone/Panel.qml) · [CallScreen.qml](../../plugins/alteringux.phone/CallScreen.qml) |
| `pomodoro` | Focus timer with daily goal, phases, stats and sounds. | Familiar loop with enough configurability. Keep current phase and next transition primary; avoid analytics competing with timer.  [manifest.json](../../plugins/alteringux.pomodoro/manifest.json) · [BarWidget.qml](../../plugins/alteringux.pomodoro/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.pomodoro/Panel.qml) |
| `pulse` | Cross-plugin activity plus one “needs action” signal and unread feed. | Strong suite-level return loop. Prioritize actionable state over raw activity and preserve source context for repeated events.  [manifest.json](../../plugins/alteringux.pulse/manifest.json) · [BarWidget.qml](../../plugins/alteringux.pulse/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.pulse/Panel.qml) |
| `recall` | Fullscreen micro-lessons and adaptive quizzes mixed with trivia. | Immersion supports memorization. Explain why an item returned and keep the take-over exit and pacing under user control.  [manifest.json](../../plugins/alteringux.recall/manifest.json) · [BarWidget.qml](../../plugins/alteringux.recall/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.recall/Panel.qml) · [Prompt.qml](../../plugins/alteringux.recall/Prompt.qml) |
| `reminders` | Guided multi-step reminder setup. | A flow is a better fit than a dense settings form. Show progress, back/cancel and the resulting reminder before completion.  [manifest.json](../../plugins/alteringux.reminders/manifest.json) · [ReminderFlow.qml](../../plugins/alteringux.reminders/ReminderFlow.qml) |
| `reposwatch` | Bar dirty/diverged count, panel per-repo staged/unstaged/untracked/ahead/behind state. | Good aggregate-to-detail mapping for developers. Preserve repo identity and distinguish local dirt from remote divergence.  [manifest.json](../../plugins/alteringux.reposwatch/manifest.json) · [BarWidget.qml](../../plugins/alteringux.reposwatch/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.reposwatch/Panel.qml) |
| `score` | Large live score with increment/decrement/undo/reset and history. | Correctly optimized for repeated, low-latency input. Shared visible Help is now added; the large score remains the hero and `Score` caption is not duplicated.  [manifest.json](../../plugins/alteringux.score/manifest.json) · [BarWidget.qml](../../plugins/alteringux.score/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.score/Panel.qml) |
| `skilldashboard` | Local skill usage/lifecycle snapshot with reversible maintenance actions. | The CLI moves removed owned skills to trash; hiding those rows made recovery unreachable in the panel. Fixed: validated removed-owned rows remain recoverable, Restore is exposed, lifecycle actions use shared keyboard-accessible controls, Remove is confirmed, and command results are shown.  [manifest.json](../../plugins/alteringux.skilldashboard/manifest.json) · [BarWidget.qml](../../plugins/alteringux.skilldashboard/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.skilldashboard/Panel.qml) |
| `sports` | Multi-sport live/upcoming/results with roster, standings and predictor. | Broad fan dashboard. The refresh service retained cached matches/articles with section timestamps, but the model discarded those flags and the panel implied an empty live list; now cached sections and their last data times are surfaced. Keep favorite teams and match detail ahead of breadth; label prediction as a model, not a result.  [manifest.json](../../plugins/alteringux.sports/manifest.json) · [BarWidget.qml](../../plugins/alteringux.sports/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.sports/Panel.qml) |
| `stocks` | Cross-market gainers/losers, price/change, ranges and trending searches. | Useful scan surface. The refresh service records Yahoo Finance and the last successful quote fetch, but the panel hid both; fixed the header to expose provider and local fetch time, including while refreshing or showing stale data. Avoid implying recommendation or investment advice.  [manifest.json](../../plugins/alteringux.stocks/manifest.json) · [BarWidget.qml](../../plugins/alteringux.stocks/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.stocks/Panel.qml) |
| `stopwatch` | Compact bar stopwatch backed by spoken CLI. | Single-purpose and low chrome is right. Keep running/paused state visible and make spoken feedback optional and predictable.  [manifest.json](../../plugins/alteringux.stopwatch/manifest.json) · [BarWidget.qml](../../plugins/alteringux.stopwatch/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.stopwatch/Panel.qml) |
| `sysmon` | Aggregate CPU/memory/temperature glance and cross-domain system panel. | Good overview role beside specialist monitors. Keep the aggregate glance distinct; link detail rather than repeating every specialist metric.  [manifest.json](../../plugins/alteringux.sysmon/manifest.json) · [BarWidget.qml](../../plugins/alteringux.sysmon/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.sysmon/Panel.qml) |
| `tempmon` | Thermal reading/threshold glance with trend and sensor detail. | Threshold-first is appropriate. Make sensor names, threshold source and alert recovery clear.  [manifest.json](../../plugins/alteringux.tempmon/manifest.json) · [BarWidget.qml](../../plugins/alteringux.tempmon/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.tempmon/Panel.qml) |
| `timers` | User-labeled elapsed-time trackers, not preset countdowns. | The count-up model matches activity timing. Keep label, start time and completion state together; prevent accidental finish/remove.  [manifest.json](../../plugins/alteringux.timers/manifest.json) · [BarWidget.qml](../../plugins/alteringux.timers/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.timers/Panel.qml) |
| `ttsplayer` | Transport for the current streaming Piper job with voice selection. | A small transport panel is right; no seek control is correct for a non-seekable stream. Explain current chunk/progress as best effort.  [manifest.json](../../plugins/alteringux.ttsplayer/manifest.json) · [BarWidget.qml](../../plugins/alteringux.ttsplayer/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.ttsplayer/Panel.qml) |
| `vpnrotate` | Wi-Fi-only Proton VPN connection/IP rotation with busy-gated controls. | Network scope guard is a strong trust choice. Keep connected endpoint, request/result and failure state visible.  [manifest.json](../../plugins/alteringux.vpnrotate/manifest.json) · [BarWidget.qml](../../plugins/alteringux.vpnrotate/BarWidget.qml) · [Panel.qml](../../plugins/alteringux.vpnrotate/Panel.qml) |
| `wordstep` | Selected text reader with speech, paced highlighting and saved stats. | Strong selection-to-reading loop. Keep voice opt-in, retain complete source text, and never advance while requested speech is paused or failed.  [manifest.json](../../plugins/alteringux.wordstep/manifest.json) · [WordStep.qml](../../plugins/alteringux.wordstep/WordStep.qml) |
## Spec: finish design-led fixes for the local plugin suite

### Problem statement

The machine has 42 first-party product plugins with intentionally different
jobs and surfaces; the previous catalog-only spec did not examine those design
choices. The current teardown found specific gaps in visible keyboard-help
discovery, Skill Dashboard recovery/actions, NewsBar refresh access, Calendar
AI action disclosure, and freshness/provenance across Dashboard, Sports,
Stocks, and NanoGPT. This spec records the package-by-package rationale and
targeted fixes. The old 40-package ledger is stale for this checkout. Broad
rendered review and package-level native interaction evidence remain open.

### Solution

Use this product/design inventory as the package-level rationale, apply the
shared Kit Help affordance to Clock and Score without flattening their distinct
calendar and score designs, repair Skill Dashboard's unreachable restore path,
fix Agentglass's packaged CLI lookup, and make NewsBar refresh keyboard and
assistive-technology reachable. Bring the review scope to all 42 first-party
manifests. Implement other changes only when current source or runtime evidence
confirms a defect; use rendered/native evidence for visible interaction and
layout claims. Keep Kit and third-party packages outside the product count.

### User stories

1. As the machine owner, I want each plugin's purpose and surface choice
   explained, so I can decide what belongs on my desktop.
2. As the owner, I want related plugins' boundaries explained, so I can tell
   Calendar from Agenda, System Monitor from its specialist monitors, and
   activity from attention.
3. As a panel user, I want visible mouse-accessible Help when keyboard help is
   available, so I can discover shortcuts without already knowing F1.
4. As a keyboard user, I want the same Help affordance to retain F1/F6
   behavior, so visible and keyboard interaction stay aligned.
5. As a scorekeeper, I want the score to remain visually primary after Help is
   added, so the panel remains fast for repeated input.
6. As a calendar user, I want month browsing and today's date to remain distinct
   from a date picker, so navigation does not imply day selection.
7. As a maintainer, I want the audit inventory to match first-party manifests,
   so new local plugins are not silently omitted from design review.
8. As a reviewer, I want source claims separated from rendered/native evidence,
   so an inventory is not misrepresented as a runtime pass.
9. As a maintainer, I want plugin-specific exceptions justified by the actual
   job, so consistency does not erase useful product differences.
10. As a user of an interruptive or AI-enabled plugin, I want consent, current
    state and exit behavior visible, so powerful behavior remains trustworthy.
11. As a Skill Dashboard user, I want removed owned skills to remain visible
    with a Restore action, so a reversible removal can actually be undone from
    the interface.
12. As a keyboard or screen-reader user, I want lifecycle actions to have
    concise names, stable focus and visible action feedback, so I can manage a
    skill without relying on mouse-only controls.
13. As the machine owner, I want the Agentglass installer to find the CLI
    shipped with the plugin, so an in-place local plugin can be installed
    without a separate checkout layout.
14. As the machine owner, I want the taskbar layout check to account for the
    NewsBar's eDP-1-only design, so fallback or external displays are checked
    against surfaces they can actually host.
15. As a keyboard or screen-reader user, I want NewsBar refresh to expose a
    named control and keyboard activation, so the feed is refreshable without
    a pointer.
16. As a calendar user, I want to know before submitting that the assistant can
    directly change events, so I can choose prompts with clear effects and
    review the returned result.
17. As a Stocks user, I want to see the data provider and last successful
    quote-fetch time, so I can judge the age of prices and spot stale data.
18. As a NanoGPT usage user, I want to see when the usage snapshot was
    collected, so I can tell whether retained quota data is current.
19. As a Sports user, I want cached matches and articles identified with their
    own last-data times, so a failed provider refresh does not look like fresh
    empty results.
20. As a Dashboard user, I want the system snapshot's age alongside its
    heading, so a previously captured summary is not presented as currently
    up to date.

### Implementation decisions

- Keep the existing 42 first-party manifest IDs as scope. `alteringux.kit` is
  shared infrastructure; `io.github.*` packages are third-party.
- Reuse `Kit.PanelHead` and its existing recovery Help behavior in Clock and
  Score. Remove duplicate in-panel F1-only copy where the visible affordance
  now covers it. Keep the calendar month grid and Score's large numeric value.
- Bind the shared header's rendered height to its implicit content height so
  titles and Help controls remain visible in its consumers. Keep shortcut
  hints in the panel footer to avoid duplicating F6 in the header.
- Extend Skill Dashboard's read snapshot with validated, trash-backed removed
  owned entries while keeping removed skills out of installed/active totals.
  Add a Restore action that routes through the existing CLI ownership and path
  guards. Use `Kit.KeyboardPanel`, `Kit.PanelKeys`, and `Kit.ActionButton` for
  panel focus and lifecycle controls; keep secondary actions collapsed until
  requested and require a second confirmation for Remove.
- Give lifecycle commands a pending and exit-status result in the panel. Do not
  report success before the CLI completes, and preserve the existing
  backup-before-remove behavior.
- Resolve Agentglass's executable from the installer package directory, which
  is the source of truth for this in-place plugin distribution.
- Replace NewsBar's refresh `MouseArea` with `Kit.ActionButton`, using its
  accessible name, keyboard activation, and native focus treatment. Keep the
  busy indicator and both-feed refresh callback.
- Disclose before Calendar AI submission that add/move/remove requests can
  directly modify entries; retain the answer area as the visible result.
- Show Yahoo Finance and the last successful quote-fetch time in Stocks panel
  metadata, including during refreshes and provider failures with cached data.
- Show the NanoGPT snapshot's collector timestamp in the panel and preserve it
  alongside the refresh-in-progress state.
- Preserve Sports cached-section health and timestamps in the model and expose
  them in the panel when the latest refresh reuses prior data.
- Show Dashboard's system snapshot age and replace the undated “Up to date”
  empty-state claim with a refresh-aware empty message.
- Keep the bar geometry check strict for visible surfaces; require NewsBar on
  its configured eDP-1 monitor and skip that surface assertion on the
  compositor's fallback output.
- Treat manifest purpose as identity evidence and source surface as current
  implementation evidence. Record intentional exceptions instead of forcing
  every package into a panel/bar template.
- Use one manifest-completeness check for both the README catalog and teardown
  rows; a first-party manifest without either row is an inventory failure.
  Do not infer runtime accessibility from declarations or compilation.
- For all other code changes, choose the smallest package-local or shared-Kit
  fix after current source or runtime evidence confirms the defect. Visible
  interaction and layout claims require rendered/native evidence.

### Testing decisions

- Review user-visible behavior: Help opens through mouse and F1, the existing
  Escape/focus-return path remains, Clock still browses months without day
  selection, and Score actions/history retain their existing behavior.
- Check that the shared panel header renders its title and Help control at its
  content height, and that shortcut hints appear once in the panel footer.
- Use the existing production QML load probe and focused action/keyboard probes
  if these components are changed again. These prove loading and specific
  interactions only; they do not prove suite-wide visual quality or AT-SPI.
- Keep removed entries visible after refresh, restore only a valid trash-backed
  user-owned path, and show the restored entry again after the action completes.
  Verify failure feedback and confirm that installed totals exclude removed
  rows.
- Account for every first-party manifest in the audit. For visual completion,
  review the actual package surface at normal and constrained width, both
  themes and enlarged text where applicable; record native gaps honestly.
- Run the isolated Agentglass installer test, the Skill Dashboard lifecycle
  regression, the production QML load probe, and the aggregate suite. The
  geometry check must pass on both the built-in output and a fallback display.
- For NewsBar, compile the changed package, confirm the accessible name and
  focusable state in source, and retain native visual/assistive-technology
  checks as open evidence until captured.
- For Calendar, keep the direct-mutation disclosure visible before submit and
  retain the assistant's completed result or failure after submission.
- For Stocks, verify valid and missing timestamps, refresh-in-progress, and
  stale-provider metadata; describe quote-fetch time without implying an
  exchange timestamp.
- For NanoGPT, verify a valid/missing snapshot timestamp and refresh-in-progress
  metadata without claiming that a failed refresh produced new data.
- For Sports, preserve cached-section flags and timestamps through parsing and
  display cached matches/articles with the corresponding section timestamp.
- For Dashboard, check missing, recent, and old system timestamps in the
  heading; verify that an empty snapshot never reads as “Up to date.”

### Out of scope

- Rewriting all 42 plugins into a uniform visual template.
- Adding telemetry, monetization, a public marketplace, or machine-independent
  product claims.
- Changing unrelated shell configuration, widget placement, domain models,
  services, or user worktree edits.
- Claiming native assistive technology, compositor, or every-plugin rendering
  passes without the corresponding evidence.

### Further notes

The product choices are intentionally diverse: passive summaries, specialist
diagnostics, long-form panels, agent tools and immersive sessions need different
interaction intensity. The suite should standardize shared mechanics while
preserving those differences.
