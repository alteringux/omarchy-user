# Sports Dashboard Plugin — Product Requirements Document

## 1. Document control

- **Product:** Sports Dashboard
- **Plugin ID:** `alteringux.sports`
- **Platform:** Omarchy shell / Quickshell
- **Owner:** AlteringUX
- **Status:** Functional first release under active refinement
- **Primary surface:** Omarchy top bar widget and anchored panel
- **Configuration:** `~/.config/omarchy/sports-config.json`
- **Runtime state:** `~/.local/state/omarchy/sports.json`

This PRD defines the product direction, user experience, data contracts, safety
boundaries, implementation phases, and extension points for a rich multi-sport
companion inside Omarchy. It intentionally separates the first useful release
from integrations that require credentials, paid quotas, or more involved
provider-specific adapters.

## 2. Problem and opportunity

Sports information is fragmented across league pages, score services, player
pages, news sites, and prediction tools. A desktop user should be able to see
what matters without opening several browser tabs, while retaining the option
to inspect a match, compare teams, read context, or ask a natural-language
question.

The plugin should answer these questions quickly:

1. Is one of my teams playing now?
2. What matches are next across my sports?
3. What happened recently?
4. Who are the players and what are their profiles and statistics?
5. Where does a team sit in its table?
6. Which side has the stronger historical and recent form?
7. What are reputable sports publications reporting?
8. Can an AI analyst explain the cached evidence without inventing facts?

## 3. Goals

### 3.1 Product goals

- Cover many sports through one consistent panel.
- Make Rugby, Football/Soccer, Basketball, and UFC/MMA useful immediately.
- Support additional sports without changing the QML structure.
- Surface live, upcoming, and finished events in a compact readable form.
- Provide team, player, standings, article, and prediction context.
- Prefer cached local data so the panel remains responsive during network delay.
- Make data freshness and missing data visible rather than implying certainty.
- Keep the panel visually expressive through sport-specific accents, glyphs,
  team badges, player thumbnails, article media, and restrained emoji.
- Keep data-fetching and prediction logic outside QML so it can be tested and
  run independently.

### 3.2 Engineering goals

- Follow the existing `alteringux.*` plugin architecture.
- Follow ADR 0002: one plugin per hobby domain; this is not a card inside
  `alteringux.dashboard`.
- Follow ADR 0005: use the shared panel text hierarchy and Kit components.
- Follow ADR 0006: CLI-first state mutation and thin QML views.
- Use tolerant parsers and atomic state writes.
- Avoid a hard dependency on paid APIs for the first release.
- Never present a model estimate as betting advice or a guaranteed outcome.

## 4. Non-goals

- Placing bets, managing bookmaker accounts, or providing financial advice.
- Guaranteeing live scores from a provider whose free tier does not provide
  real-time event updates.
- Scraping arbitrary websites from QML.
- Replacing official league, team, or athlete pages.
- Building a social feed, chat room, fantasy league, or account system.
- Storing API secrets in the plugin source tree.
- Calling an AI model for every refresh or every bar repaint.

## 5. Users and primary journeys

### 5.1 The quick glance

The bar widget displays a trophy glyph and the most relevant current item:

- a favourite team's live score when available;
- otherwise another live score;
- otherwise the next relevant fixture;
- otherwise `Sports`.

Hover text supplies the league, match time, and live-match count. Clicking the
widget opens the panel. The widget must remain useful even when the network is
unavailable by showing the last successful cache and its update time.

### 5.2 The match follower

1. Click the bar widget.
2. Stay on **Live** for current scores and period/elapsed information.
3. Switch to **Upcoming** for the next fixtures.
4. Switch to **Results** for recently completed matches.
5. Use the sport pills to narrow the view.
6. Add a favourite team in the configuration to promote it in the bar and panel.

### 5.3 The UFC/MMA follower

UFC/MMA is represented by TheSportsDB's `Fighting` sport name and UFC league
ID `4443`. The UI label is **UFC / MMA**. The user can filter to Fighting, see
scheduled UFC events when available from the configured league, read UFC news,
and use the same article and AI context tools as other sports.

The plugin must keep the provider's sport terminology in the stored data while
using a friendly label in the UI. This allows future MMA promotions or combat
sports feeds to coexist without a schema migration.

### 5.4 The player researcher

1. Choose **Players**.
2. Select a sport or leave the view on All.
3. Search by player, position, or team.
4. Click a row to expand biography fields, nationality, physical information,
   description, thumbnail, and future season-stat fields.

Player data is loaded for configured favourite teams first. This avoids an
unbounded request for every team appearing in every league.

### 5.5 The analyst

1. Choose **Predict**.
2. Select the home and away teams.
3. Run the local weighted comparison.
4. Read the predicted side, confidence, sample size, and factor breakdown.
5. Optionally ask the AI analyst for a plain-language explanation.

The prediction card must state that it is a comparison, not betting advice. A
small sample, missing standings, or no finished matches must lower confidence or
produce an explicit error rather than a fabricated result.

### 5.6 The news reader

1. Choose **Articles**.
2. Filter to a sport such as UFC / MMA, Rugby, or Basketball.
3. Review title, source, age, summary, and optional image.
4. Click a card to open the original URL in the default browser.

Only configured HTTP(S) feed URLs are accepted. The plugin does not rewrite or
summarize an article before the user opens it.

## 6. Supported sports

### 6.1 Initial catalog

The catalog is data-driven in `Model.js` and currently includes distinct glyph
and accent metadata for:

- Football/Soccer
- Rugby
- Basketball
- UFC/MMA (`Fighting`)
- Boxing
- American Football
- Baseball
- Cricket
- Tennis
- Ice Hockey
- Motorsport
- Golf
- Cycling
- Volleyball
- Handball

The provider may expose additional sports. Unknown names remain selectable and
fall back to a trophy glyph and neutral accent instead of breaking the panel.

### 6.2 Configuration policy

`activeSports` controls which sports are polled. The panel includes configured
sports even when no event is currently returned, so a user can select UFC or a
less frequent sport before its next event occurs.

Leagues are optional per sport. A sport with no league entry can still use the
provider's day-sweep endpoint and configured article feeds. A sport-specific
league ID enables broader upcoming and historical coverage.

### 6.3 First-release seeded coverage

The seed covers:

- English Premier League (`4328`)
- English Premiership Rugby (`4414`)
- French Top 14 (`4430`)
- Australian National Rugby League (`4416`)
- NBA (`4387`)
- UFC (`4443`)

The user can add leagues and favourite teams without changing plugin code.

## 7. User experience and visual system

### 7.1 Bar widget

The bar widget follows the established `alteringux.stocks` pattern:

- background refresh through a `Process`;
- watched local state through `Kit.Store`;
- a bounded refresh cadence;
- a compact animated `TickerTape`;
- an `AttentionDot` for waiting or warning conditions;
- IPC methods for open, close, toggle, refresh, and status.

The widget must not show a long scrolling sentence that obscures adjacent bar
items. Match names are truncated by the shared component when necessary.

### 7.2 Panel structure

The panel is an anchored, vertically scrollable dashboard:

1. `Kit.PanelHead` with Sports glyph, title, live count, and Refresh button.
2. A wrapping sport filter row so a large catalog does not overflow horizontally.
3. A tab row: Live, Upcoming, Results, Players, Table, Articles, Predict.
4. A contextual section heading.
5. The selected tab's cards or empty state.
6. Ask the Analyst field and answer area.
7. Keyboard hint row: `Enter: refresh now · Esc: close`.

The panel must never require a network request merely to open. It renders the
last cache immediately and updates when the watched state changes.

### 7.3 Colour semantics

Sport accents are stable and deterministic:

- Soccer: teal
- Rugby: amber
- Basketball: orange
- Fighting and Boxing: pink/red
- American Football: violet
- Baseball: gold
- Cricket: sky blue
- Tennis: lime
- Motorsport: rose
- Ice Hockey: ice blue
- Golf: green
- Cycling: lavender
- Volleyball: pink
- Handball: orange

These accents are used for selected pills, sport glyphs, match score emphasis,
prediction bars, and small card spines. Text contrast continues to come from the
active Omarchy theme; sport colours are accents, not replacement backgrounds.

### 7.4 Images and media

The plugin may display remote media only when a provider supplies a valid
HTTP(S) URL:

- team badges from TheSportsDB team records;
- player thumbnails from roster records;
- article images from RSS `media:content`, `media:thumbnail`, or `enclosure`.

Images load asynchronously, preserve aspect ratio, and disappear cleanly when
unavailable. Every image has a text fallback: team name, player name, or source.
The UI must not fail because an image host is slow or unavailable.

Emoji identify sports directly in the selector and match cards so the
dashboard remains recognizable when a nerd font is unavailable. Small semantic
labels may use additional emoji such as `📰` Articles and `🤖` model picks.

Match cards expose provider-supplied videos plus YouTube searches for highlights
and official coverage. The plugin must not link to unlicensed stream
aggregators or imply that a search result is a guaranteed live stream.

## 8. Data sources and provider strategy

### 8.1 TheSportsDB

The first provider is TheSportsDB's free JSON API:

`https://www.thesportsdb.com/api/v1/json/{apiKey}/`

Used endpoints include:

- `eventsnextleague.php`
- `eventspastleague.php`
- `eventsday.php`
- `eventsnext.php`
- `eventslast.php`
- `lookuptable.php`
- `lookup_all_players.php`
- `lookupteam.php`
- `lookupevent.php`
- `lookupeventstats.php`

The public development key is `3`; users should configure an appropriate key
for sustained or production use. The free tier does not guarantee true
real-time scores, so the product must distinguish scheduled, cached, and
in-play-looking records from authoritative live coverage.

References:

- [TheSportsDB API documentation](https://www.thesportsdb.com/documentation)
- [TheSportsDB Fighting sport](https://www.thesportsdb.com/sport/fighting)
- [TheSportsDB UFC league](https://www.thesportsdb.com/league/4443-UFC)

### 8.2 RSS and Atom article feeds

Articles use configured RSS/Atom URLs. The refresh script parses titles, links,
published timestamps, summaries, source hostnames, and optional media URLs with
Python's standard-library XML parser. Bad XML, a non-HTTP URL, or a failed feed
produces no articles from that feed and does not discard match data.

The seed includes BBC feeds for Football, Rugby, and Basketball plus the UFC
news feed. Feeds remain user-editable because providers can change URLs or
terms. The card always links back to the original publisher.

### 8.3 Optional future providers

Provider adapters may be added when the free source lacks coverage:

- API-Sports / RapidAPI for premium live scores and league-specific detail;
- Sportradar or SportsDataIO for licensed high-volume data;
- ESPN public endpoints where their terms and stability permit;
- official league or team feeds for authoritative schedules;
- separate motorsport, golf, tennis, or combat-sport feeds where coverage is
  better than the generic provider.

Each adapter must map into the same compact event/player/table/article shapes,
identify its freshness and source, and be selectable in configuration. A new
provider must not leak provider-specific JSON into QML.

## 9. Local data contracts

### 9.1 Configuration

`~/.config/omarchy/sports-config.json`:

```json
{
  "version": 1,
  "apiKey": "3",
  "activeSports": ["Soccer", "Rugby", "Basketball", "Fighting"],
  "favouriteTeams": [
    { "idTeam": "133604", "name": "Arsenal", "sport": "Soccer" }
  ],
  "refreshSeconds": 300,
  "liveRefreshSeconds": 60,
  "tableSports": ["Soccer", "Basketball"],
  "players": true,
  "articlesFeeds": {
    "Fighting": ["https://www.ufc.com/rss/news"]
  },
  "leagues": {
    "Fighting": [{ "id": "4443", "name": "UFC" }]
  }
}
```

Unknown keys are preserved by the QML config reader and ignored by the current
fetcher, allowing forward-compatible user configuration.

### 9.2 State

`~/.local/state/omarchy/sports.json`:

{
  "version": 1,
  "updatedAt": "2026-09-13T00:00:00Z",
  "live": [],
  "upcoming": [],
  "results": [],
  "articles": [],
  "players": {},
  "standings": {},
  "teams": {},
  "predictions": {},
  "favouriteTeams": [],
  "season": "2026-2027"
}
```

Events use compact fields such as `id`, `sport`, `league`, `eventName`,
`homeTeam`, `awayTeam`, `homeScore`, `awayScore`, `dateEvent`, `strTimestamp`,
`venue`, `status`, `elapsed`, `videoUrl`, `youtubeHighlightsUrl`,
`officialCoverageUrl`, and `stats`.

Predictions are keyed by normalized `sport|homeTeam|awayTeam` and contain the
predicted winner, confidence, factor breakdown, sample counts, human-readable
reason, event id, saved timestamp, and structured error when history is
insufficient.

Articles use `title`, `url`, `source`, `sport`, `published`, `summary`, and an
optional `image`. All sections are arrays or maps with safe empty defaults.

### 9.3 Atomicity and freshness

The fetcher writes a temporary sibling file and uses `os.replace` so the QML
watcher never adopts a half-written document. The state timestamp records the
successful write time. A section may be empty because its endpoint failed; the
refresh command itself still completes with a valid state when possible.

## 10. Executables and responsibilities

### 10.1 `bin/omarchy-sports-refresh`

A small guarded shell wrapper invokes `sports_fetch.py`. It accepts optional
config, state, and timeout arguments and keeps the plugin's established bug
reporting integration.

### 10.2 `bin/sports_fetch.py`

Responsibilities:

- load and merge configuration defaults;
- fetch configured league, favourite-team, table, player, and day data;
- fetch configured RSS/Atom feeds;
- compact and validate provider records;
- deduplicate events and article URLs;
- write one atomic state document;
- degrade independently when one endpoint or feed fails.

It must not invoke an AI model.

### 10.3 `bin/omarchy-sports-predict`

The Python predictor reads cached state, not the network. It compares recent
finished matches, head-to-head results, home/away performance, and standings.
The current weighted model is:

- recent form: 40%;
- head-to-head: 25%;
- home advantage: 20%;
- standing: 15%.

The output is JSON with the two teams, predicted winner, confidence, factor
breakdown, sample counts, a human-readable reason, and an error field. Missing
factors are omitted from the weighted average; no-data input returns a
structured non-zero error.

Every refresh automatically evaluates distinct team matchups in the live and
upcoming sections and persists the latest result under `predictions`. Combat
events without two named teams are skipped rather than given a fabricated
prediction.

### 10.3.1 `bin/omarchy-sports-event`

The event-detail command reads one event and its provider statistics from
TheSportsDB for the detail view. Missing provider statistics produce an empty
stats list while preserving the event summary.

Future models may add ELO or logistic regression, but model selection must be
explicit and the card must identify the model used.

### 10.3.2 `bin/omarchy-sports-notify`

The notifier reads cached live events and sends one deduplicated
`omarchy-pulse log alteringux.sports ... --notify` event when a match enters a
known in-play status. Delivery is recorded in a separate retained marker so
refreshes cannot re-alert the same event.

### 10.3.3 User timers

The installed user timers refresh matches, articles, standings, and predictions
every five minutes, then check for game starts every minute. They remain
independent of the shell process, so updates continue when the dashboard is
closed.

### 10.4 `bin/omarchy-sports-ai`

The AI wrapper accepts a question, sport, and state path. It builds a bounded
context from cached live, upcoming, and recent match data, then invokes the
existing `llm-blurb` route. The system prompt requires concise, stats-grounded
answers and forbids invented scores. Backend failure is shown as unavailable
rather than treated as a data result.

## 11. QML component requirements

### 11.1 `BarWidget.qml`

- Read config from the user-level config directory.
- Watch `sports.json` through `Kit.Store`.
- Use bounded refresh and avoid refresh storms across screens.
- Expose open, close, toggle, refresh, and status IPC.
- Show live/favourite/upcoming summary.

### 11.2 `Panel.qml`

- Use `KeyboardPanel`, `Kit.PanelScroll`, `Kit.PanelHead`, `Kit.EmptyState`,
  and shared typography tokens.
- Keep the sport filter wrapping and scrollable.
- Handle all tabs without creating one component per sport.
- Validate article URLs before launching `xdg-open`.
- Keep AI and prediction subprocesses separate and observable.

### 11.3 `MatchCard.qml`

- Render league, sport glyph, home and away names, scores or time, and status.
- Highlight favourite and live matches.
- Display team badges when cached.
- Use sport-specific accent colors.

### 11.4 `PlayerCard.qml`

- Render name, number, position, and optional thumbnail.
- Expand in place for biography and future season-stat fields.
- Keep missing fields invisible rather than showing `undefined`.

### 11.5 `ArticleCard.qml`

- Render title, source, published time, summary, and optional image.
- Open only validated HTTP(S) URLs.
- Fall back to a text-only card when media cannot load.

### 11.6 `PredictionCard.qml`

- Render winner, confidence, sample counts, and factor rows.
- Use the selected sport accent.
- Show errors and the non-betting disclaimer clearly.

## 12. Accessibility and resilience

- Every visual icon has adjacent or tooltip text.
- Long names use elision and remain available through tooltip/context text.
- Keyboard focus must reach text inputs and buttons.
- Esc closes the panel; Enter triggers refresh from the panel context.
- Empty states say what happened and how to recover.
- Network errors never crash the shell or erase a previously valid state before
  a new valid state is written.
- Remote images are optional and asynchronous.
- AI responses are bounded in length and treated as commentary, not source data.

## 13. Test requirements

### 13.1 Pure model tests

`test/model.test.js` must cover:

- malformed and empty state parsing;
- per-section fallback behavior;
- score and time formatting;
- favourite-team prioritization;
- sorting upcoming fixtures;
- prediction output parsing;
- UFC/Fighting label, glyph, and accent metadata;
- unknown-sport fallback.

### 13.2 Fetcher tests

`sports_fetch_test.py` must remain fully offline and cover:

- event compaction and missing IDs;
- null score handling;
- inactive sports not being requested;
- merged league and favourite-team records;
- day-sweep placement;
- standings, player, and team compaction;
- atomic state output;
- malformed or unsafe article URLs;
- article media metadata.

### 13.3 Predictor tests

`sports_predict_test.py` must cover:

- known weighted output;
- no finished-match error;
- unfinished records being ignored;
- head-to-head counting;
- home advantage;
- standing-derived factor;
- non-zero CLI error exit.

### 13.4 Runtime smoke checks

A release check must:

1. Parse all JSON configuration files.
2. Run all offline test suites.
3. Run a real refresh with the seeded configuration.
4. Confirm `sports.json` has valid version and array/map sections.
5. Confirm the shell registers `alteringux.sports`.
6. Confirm shell IPC ping, sports status, open, and close.
7. Visually inspect the bar ticker and open panel.
8. Confirm no shell journal error is emitted by the sports plugin.

## 14. Rollout phases

### Phase 1 — useful multi-sport cache

- TheSportsDB league and day data.
- Football, Rugby, Basketball, Fighting/UFC coverage.
- Bar ticker, Live, Upcoming, Results.
- Configurable active sports and favourites.

### Phase 2 — research dashboard

- Player roster and thumbnail support.
- Team badges and team profiles.
- Tables and form history.
- Article feeds and media cards.
- Sport-specific visual accents.

### Phase 3 — analysis

- Weighted cached predictor.
- Explicit confidence and sample explanations.
- AI analyst with cached context.
- Better per-sport factor normalization.

### Phase 4 — provider depth

- Optional live-score provider adapter.
- Provider freshness labels and source diagnostics.
- Event timelines, lineups, injuries, and discipline where licensed data
  supports them.
- Sport-specific detail modules only when the shared event contract remains
  coherent.

### Phase 5 — personalization

- Edit-in-place favourite teams and feed URLs.
- Optional notification hooks for a favourite match start or final score.
- Persisted selected sport and selected tab.
- Compact bar cycling preferences.

## 15. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Free provider rate limits | Poll slowly, deduplicate requests, cache locally, allow a user key. |
| Free tier lacks true live scores | Label freshness honestly and support an optional provider adapter. |
| Provider schema changes | Compact at one boundary, use tolerant parsing, keep fixtures offline. |
| Too many active sports cause slow refresh | Keep requests bounded, allow activeSports selection, isolate feed failures. |
| Remote image hosts fail | Asynchronous load plus text fallback. |
| AI hallucinates a result | Pass only cached context, bounded prompt, require uncertainty wording. |
| Prediction appears authoritative | Show sample size, factor breakdown, and disclaimer. |
| Panel becomes too tall | Outer scroll, card caps, wrapping controls, bounded result counts. |
| User configuration is overwritten | Keep config outside the plugin source tree and watch it independently. |

## 16. Existing implementation references

The plugin is intentionally based on patterns already present in this Omarchy
configuration:

- `alteringux.stocks/BarWidget.qml` — bar widget lifecycle, ticker, refresh,
  Store watching, and IPC.
- `alteringux.stocks/Panel.qml` — card grids, filter pills, panel layout, and
  empty states.
- `alteringux.stocks/Model.js` — pure parsing and formatting helpers.
- `alteringux.newsbar/NewsBar.qml` — RSS state, article opening, and feed
  resilience.
- `alteringux.newsbar/bin/stories_fetch.py` — standard-library feed parsing
  and bounded derived content.
- `alteringux.calendar/Panel.qml` — panel controls, separators, and AI row.
- `alteringux.kit/Store.qml` — user/state file location, watch mode, polling,
  debounce, and atomic writes.
- `alteringux.kit/PanelHead.qml` — shared panel title and meta hierarchy.
- `docs/adr/0002-one-plugin-per-hobby-domain.md` — domain ownership.
- `docs/adr/0005-panel-text-hierarchy.md` — type ramp and spacing.
- `docs/adr/0006-cli-first-plugins.md` — state mutation outside QML.
- `docs/adr/0001-local-keyboard-shortcuts-per-plugin.md` — keyboard semantics.

## 17. Definition of success

The plugin is successful when a user can install or enable it, open one bar
widget, switch from Rugby to Basketball or UFC/MMA without editing code, see
cached fixtures and results, inspect players and tables, read current configured
articles with optional imagery, run a transparent comparison, and ask for an AI
overview — while the shell remains responsive and the UI stays truthful when a
provider or image is unavailable.
