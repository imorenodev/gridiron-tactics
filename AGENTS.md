# Agent Instructions

This repository is **Gridiron Tactics**, a Marvel-Snap-style card game with a football theme, being ported from a single-file HTML/JS prototype to Defold for iOS/Android release. The project root is the folder containing `game.project`.

**`CLAUDE.md` in the project root is the source of truth for conventions, hard rules, the phase log, and per-phase notes.** Read it first for anything beyond folder shape and file formats. If this file conflicts with `CLAUDE.md`, `CLAUDE.md` wins — flag the conflict and stop.

## Project map

- **Root config**: `game.project`
- **Top-level screen router**: `main/main.collection` instantiates `main/loader.go` (+ `loader.script`), which owns two collection proxies — `proxy_menu` (→ `main/ui/menu.collection`) and `proxy_match` (→ `main/match/match.collection`) — and the persisted save table.
- **Main game content**: `main/`
    - `match/` — in-match game objects and scripts (`match.collection`, `match.script`, `lane.script` × 3 instances, `card_factory.script`, `card.script`, `card.go`)
    - `ui/` — GUI scenes and scripts (`menu.collection` + `menu.gui` + `menu.gui_script`; `hud.gui` + `hud.gui_script` embedded in `match.collection`)
    - `data/` — pure-data Lua modules (`cards.lua`; more pool/meta data here in later phases)
    - `state/` — stateful Lua modules (`match_state.lua`, `save.lua`, `messages.lua`)
    - `ai/` — CPU logic (`cpu.lua` — greedy heuristic ported from the HTML)
- **Input bindings**: `input/game.input_binding`
- **Render**: `render/` is **reserved and intentionally empty** (only `.gitkeep`). The project uses `/builtins/render/default.renderc`. **Do not add a custom render script** without first verifying that `gui.pick_node` registers taps on visible GUI buttons (CLAUDE.md hard rule #11 — a previous custom letterbox render broke input picking).
- **Assets**: `assets/images/ui/` holds PNGs from the HTML prototype (migrated from `src/assets/` in Phase 2.5; not yet wired up — atlas building lands in a future asset-integration phase). `assets/fonts/` is `.gitkeep` only.
- **Dependencies (read-only context)**: `.deps/builtins/` only (Defold engine builtins, populated by the `defold-project-setup` skill). `.deps/` is git-ignored.

### Key `game.project` settings

- **Bootstrap collection**: `/main/main.collectionc`
- **Bootstrap render**: `/builtins/render/default.renderc` (default; do not override)
- **Display resolution**: 1170 × 2532, portrait. Designed for iPhone-class screens; do not add landscape support.
- **Bundle ID** (iOS) / **package** (Android): `com.imoreno.gridirontactics`
- **`script.shared_state = 1`** — Lua modules under `main/state/`, `main/data/`, `main/ai/` are loaded once per process and shared across all scripts. Module-local state (e.g. `match_state.lua`'s tables) is process-wide; treat it as a singleton, mutate only via exported functions.

**Resource paths in `game.project`**: Values like `main_collection`, `game_binding`, `app_icon` use Defold resource identifiers. A trailing `c` suffix denotes compiled resources and is expected — do not treat it as a typo.

## Dependencies

- **No `[project] dependencies#N` entries in `game.project`.** Per CLAUDE.md hard rule #9, the project is Defold-stdlib-only. Adding a third-party library (including well-known ones like `defold-tween`) requires explicit approval first.
- After any change to dependencies in `game.project`, re-run the `defold-project-setup` skill (`python .claude/skills/defold-project-setup/scripts/fetch_deps.py`) to refresh `.deps/`.

## Include directories

- Use `.deps/` as an include directory for resolving module references and understanding dependency APIs.
- **NEVER modify any files inside `.deps/`** - these are downloaded dependencies provided strictly as read-only context.

## Defold file formats

- **Lua scripts**: `.lua`, `.script`, `.gui_script`, `.render_script`, `.editor_script`.
- **Metadata assets** (Protocol Buffer Text Format): `.collection`, `.go`, `.sprite`, `.tilemap`, `.tilesource`, `.atlas`, `.font`, `.particlefx`, `.sound`, `.label`, `.gui`, `.model`, `.mesh`, `.material`, `.collisionobject`, `.texture_profiles`, `.display_profiles`.
- **Manifests** (YAML): `.appmanifest`, `.manifest` - platform-specific libraries and build flags.
- **Buffers** (JSON): `.buffer` - streams of data (positions, colors, etc.) used as input for Mesh components.
- **Shaders** (GLSL): `.vp`, `.fp`, `.glsl`.
- **Project config** (INI): `game.project`.
- **Properties** (INI): `game.properties`, `ext.properties` - parameters available in `game.project`.
- **2D assets**: `.png`, `.jpg`.
- **3D assets** (GTLF): `.gltf`, `.glb`.
- **Sound assets**: `.ogg`, `.wav`, `.opus` (OPUS requires modification of the appmanifest).

## Screen routing

This project does **not** use Monarch. Screens switch via Defold collection proxies owned by `main/loader.go`:

- `loader.script` sequences `disable → final → unload` on the outgoing proxy and `load → init → enable` on the incoming proxy via the `proxy_unloaded` / `proxy_loaded` callbacks.
- Each screen collection has `name: "<screen>"` (so the collection's socket is `<screen>`). Cross-socket URLs are `<screen>:/gui#gui` from the loader and `main:/loader#script` back from a screen.
- Each screen's GUI lives on an embedded game object with id `"gui"` and a GUI component also id'd `"gui"` — pointing at `/main/ui/<screen>.gui`. Keep these ids stable.

When adding a new screen, follow this pattern: create `main/ui/<name>.collection` (with `name: "<name>"`) that embeds a `gui` GO, plus a new `#proxy_<name>` collection-proxy component on `loader.go`, and extend `loader.script` to route to it.

The `monarch-screen-setup` skill in `.claude/skills/` is **not applicable** to this project — do not load it.

## Editing Defold assets

When creating or editing Defold asset files, use the corresponding `defold-*-editing` skill to get the correct file format and structure. Always load the skill **before** writing or modifying the file.

When writing performance-critical math code or optimizing vector/quaternion/matrix operations, load the `xmath-usage` skill first.

## Code style guidelines

### Lua scripts (.lua, .script, .gui_script, .render_script, .editor_script)

- **Indentation**: 1 tab (4 spaces).
- **Naming**: `snake_case` for variables, functions, files, and folders. Keep resource paths absolute (`/assets/...`) where Defold expects them.
- **Comments**:
  - Use **LuaCATS** (`---@...`) annotations for types, module/public API docs.
- **Whitespace**:
  - Empty lines must be truly empty (no spaces/tabs).
  - Avoid trailing whitespace.
- **Defold API**: strictly follow the Defold API - always verify against the official documentation using the `defold-api-fetch` skill. There are no hidden or undocumented APIs - only use functions, messages, and properties that are explicitly described in the docs. For conceptual guidance on how Defold features work (components, physics, rendering, input, etc.), use the `defold-docs-fetch` skill. For practical implementation patterns and sample code, use the `defold-examples-fetch` skill.
- **Defensive checks**: Do NOT assume data is missing or constantly re-check field existence in tables. If YOU set a field, it EXISTS. Similarly, do NOT check for standard Lua API availability (e.g., `io` and `io.open` always exist in standard Lua). Avoid unnecessary defensive programming.
- **Paradigm**: do not use metatables or imitate classes. Use functional, data-based structures only.
- **Logging**: use `print()` to look at the game state. Add logs for transactions, initializations, important events.
- **GUI and game state separation**: GUI scripts (`.gui_script`) should NOT directly access game logic modules. All communication between game logic and UI must be message-based (`msg.post()`) to maintain clear separation of concerns. GUI should be purely data-driven, receiving all necessary data through messages and updating its display accordingly. This ensures UI remains decoupled from game implementation details.
- **Script instance state**: In `.script`, `.gui_script`, `.render_script` files, store instance-specific state in the `self` table, NOT in local module variables. Local variables at the module level are shared across ALL instances of the script, which causes bugs when multiple instances exist. Use `self.my_variable` instead of `local my_variable`. Not applicable for local functions - keep them local. If you need to call local function that it's defined below, to use forward declarations or reorganize the functions.
- **Local functions**: NEVER create local functions inside other functions. Local functions are only allowed at module scope. Anonymous lambda functions (inline callbacks) are acceptable.
- **require**:
  - Always call `require` with parentheses: `require("module")`, NOT `require "module"`.
  - Use dot notation for module paths relative to the project root: `require("main.state.messages")`, NOT `require("/main/state/messages")`.
  - Do NOT use leading slashes in require paths.
  - This project's real examples: `require("main.state.messages")`, `require("main.state.match_state")`, `require("main.state.save")`, `require("main.data.cards")`, `require("main.ai.cpu")`.
- **Hash values**: `hash("...")` can be left inline without premature optimization. It's acceptable to use `message_id == hash("trigger_response")` directly. If you need to reuse a hash value multiple times, you can declare it as a module-level constant in `UPPER_CASE` format: `local TRIGGER_RESPONSE = hash("trigger_response")`.
- **Constants**: Module-level constants can be declared as local variables in `UPPER_CASE` format: `local TRIGGER_RESPONSE = hash("trigger_response")`, `local MAX_HEALTH = 100`.
- **msg.url format**: Always remember the format `[socket:][path][#fragment]`:
  - `socket` - collection name (world)
  - `path` - game object instance id (can be relative or global)
  - `fragment` - component id
  - Shorthands: `"."` for current game object, `"#"` for current component
  - Examples: `msg.url("#my_component")`, `msg.url("collection:/path/to/go#component")`, `msg.url(socket, path, fragment)`, `msg.url(nil, hash("id"), hash("script"))`, `msg.url(nil, go.get_id("physics"), "collisionobject")`

### Python

- Write for Python 3.11. Do NOT write code to support earlier versions of Python. Always use modern Python practices appropriate for Python 3.11. Always use full type annotations, generics, and other modern practices.

## Shell

- **Windows**: use PowerShell.
- **Linux**: use bash.
- **macOS**: use zsh.

## Commands

All commands run from the project root (the folder with `game.project`).

- **Build & Run via editor** - use the `defold-project-build` skill. Requires the Defold editor to be running with the project open. Builds the project, returns compilation errors, and launches the game if the build succeeds.

## Validation checklist

- Build via the running editor succeeds (`defold-project-build` skill).

## Important repo-specific caveats

- **Git commit messages**: use the following format: `Short description` in English language ONLY.
