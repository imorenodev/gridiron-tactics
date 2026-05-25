# Claude Code Prompt — Phase 0: Defold Vertical Slice

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** It is the source of truth for conventions, file layout, hard rules, and naming. Every file you create must conform to it.

If this prompt conflicts with `CLAUDE.md`, surface the conflict in your response and stop. Do not silently resolve it.

## What this is

This is the **vertical slice prompt** for Gridiron Tactics' port from HTML/JS to Defold. The goal is not to port any real game logic. The goal is to produce a runnable Defold project that proves the entire pipeline works end-to-end:

- The project loads in the Defold editor without errors.
- The build runs on macOS via the Defold editor's run button.
- Input handling works (mouse and touch).
- A GUI scene renders correctly at the design resolution with proper scaling.
- A game-world collection with game objects spawns and updates.
- Atlas-based sprite rendering works.
- State persists across screens (menu → match → menu).
- The basic structure of `main/`, `assets/`, render config, and input bindings is in place for future work to extend.

Once this slice runs on the developer's Mac, we move to designing the real port phases. This is foundation, not gameplay.

## Hard rules

These override anything else. If you find yourself violating one, stop and ask.

1. **Single-purpose files only.** Every `.script`, `.gui_script`, `.lua` module does one thing. No god-files.
2. **Follow `CLAUDE.md`'s file layout exactly.** Do not invent new top-level folders. Do not move files to "tidier" locations.
3. **No game logic in this prompt.** No card definitions beyond a single hardcoded test card. No real lane math. No AI. No save/load. No leveling. The temptation will be to "do a little more while we're here" — resist it. The slice is for proving the engine, not previewing the game.
4. **Use Defold's default render script as the base.** Customize only the minimum needed for 1170×2532 portrait with fit-to-shortest-axis scaling. Do not write a render script from scratch.
5. **No third-party libraries.** Defold stdlib only.
6. **Pre-compute all hashes** at the top of each script that uses them. Per `CLAUDE.md`.
7. **All identifiers in snake_case.** Per `CLAUDE.md`. No camelCase carried over from the HTML version.
8. **Bundle ID is `com.imoreno.gridirontactics`.** Set this in `game.project`.
9. **Portrait orientation locked.** Set in `game.project`.
10. **Do not generate placeholder asset PNGs.** Reference them by atlas name. Real assets get added by the developer in a later step. For this slice, use Defold's built-in primitives (box nodes, colored sprites) where assets would normally go.
11. **At the end, update `CLAUDE.md`** with a "Phase 0 complete" note and any conventions you established that weren't in the original doc.

## Sub-phases

The slice is broken into sub-phases. Each ends with a `// === STOP for developer review ===` marker. **Stop after each sub-phase, wait for the developer to confirm before proceeding.** This lets them open the project in Defold between phases and verify nothing's broken.

---

### Sub-phase 0.1 — Project skeleton

Create the Defold project structure.

**Files to create:**

- `game.project` — Defold project config. Set:
    - `[project] title = Gridiron Tactics`
    - `[project] version = 0.1.0`
    - `[display] width = 1170`
    - `[display] height = 2532`
    - `[display] fullscreen = 1` (on mobile builds)
    - `[display] update_frequency = 60`
    - `[ios] bundle_identifier = com.imoreno.gridirontactics`
    - `[android] package = com.imoreno.gridirontactics`
    - `[input] game_binding = /input/game.input_binding`
    - `[bootstrap] main_collection = /main/main.collectionc`
    - `[bootstrap] render = /builtins/render/default.renderc` (we'll swap to our custom one in 0.2)
- `input/game.input_binding` — bind:
    - `MOUSE_BUTTON_LEFT` → action `touch`
    - `TOUCH_1` → action `touch`
    - `KEY_ESC` → action `back` (for editor convenience)
- `main/main.collection` — empty collection with one game object `loader` containing a single script component pointing to `main/loader.script`.
- `main/loader.script` — initial bootstrapper. On `init`, it acquires input focus and loads the menu GUI as a proxy. (Use `msg.post` to load the menu scene.)
- Empty placeholder folders: `main/match/`, `main/data/`, `main/state/`, `main/ai/`, `main/ui/`, `assets/`, `assets/images/`, `assets/fonts/`, `render/`.
- `.gitignore` — Defold-appropriate (ignore `build/`, `.internal/`, `*.zip`).

**Acceptance criteria for 0.1:**

- Opening the project in Defold editor shows no red error markers.
- Running the project shows a black/empty window at the configured resolution.
- No console errors on startup.
- `CLAUDE.md`'s file layout matches what's on disk (minus files we'll add in later sub-phases).

`// === STOP for developer review ===`

---

### Sub-phase 0.2 — Render scaling

Set up the custom render script for fit-to-shortest-axis scaling so the game works on any portrait device.

**Files to create:**

- `render/gridiron.render_script` — based on Defold's default render script (`/builtins/render/default.render_script`), modified to:
    - Read design resolution from `game.project` (`display.width`, `display.height`).
    - Read actual viewport size from `render.get_window_width()` / `render.get_window_height()`.
    - Compute scale factor as `math.min(window_w / design_w, window_h / design_h)`.
    - Center the scaled viewport, letterboxing any extra space.
    - Clear the letterbox area to dark green (`#0a1410` matching the HTML version's `body` background).
- `render/gridiron.render` — the render config pointing to the script.
- Update `game.project`'s `[bootstrap] render` to `/render/gridiron.renderc`.

**Acceptance criteria for 0.2:**

- Project runs at 1170×2532 in editor preview.
- Resizing the preview window letterboxes correctly (no stretching, no clipping of gameplay area).
- Letterbox color matches `#0a1410`.
- Reference: Defold has an official manual page on render script customization. Stay close to that pattern; don't invent new abstractions.

`// === STOP for developer review ===`

---

### Sub-phase 0.3 — Menu screen

A simple menu GUI scene that's the entry point.

**Files to create:**

- `main/ui/menu.gui` — GUI scene with:
    - Background box node, full screen, dark green color matching the HTML body.
    - Centered title text "GRIDIRON TACTICS" using Defold's built-in default font (we'll add the real fonts later). Font size large, color white.
    - Subtitle text "FIRST TO 100 YARDS" below the title, smaller, muted color.
    - One button: a box node with text "PLAY" centered inside, anchored 60% down the screen. Pick any reasonable button styling using flat colors — no images.
- `main/ui/menu.gui_script` — handles input:
    - `init`: acquire input focus.
    - `on_input`: detect "touch" action on the play button using `gui.pick_node`. On tap, post `msg.post("main:/loader", hash("show_match"))`.
- Update `main/loader.script` to:
    - On `init`: load the menu GUI as a proxy and enable it.
    - On message `show_match`: unload menu, load match GUI + match collection.
    - On message `show_menu`: unload match, reload menu.
    - Use Defold's collection proxy pattern (`#proxy_menu`, `#proxy_match` components on the loader game object).

**Acceptance criteria for 0.3:**

- Launching the game shows the menu.
- Tapping the PLAY button transitions to a blank match screen (which we'll fill in 0.4 — for now, just unload menu and show a different background color, e.g., field green `#3a803a`).
- No errors on screen transition.
- The transition is instant (no animations in this slice).

`// === STOP for developer review ===`

---

### Sub-phase 0.4 — Match screen scaffold

The match screen has the structural skeleton: scoreboard area, one lane, hand area. No real cards or game logic — just enough to prove the layout and input flow.

**Files to create:**

- `main/match/match.collection` — game world for the match. Contains:
    - One `lane.go` game object positioned at design center (585, 1266).
    - One `card_factory.go` game object with a factory component (we'll set the prototype next).
- `main/match/card.go` — a prefab game object with:
    - A sprite component (will use the `cards` atlas later; for now, use a solid-color box via `box.go`-style placeholder).
    - A `main/match/card.script` script component.
- `main/match/card.script` — minimal:
    - `init`: store `self.played = false`.
    - On message `card.play`: set position to lane center, set `self.played = true`. Post message back to lane.
- `main/match/lane.script` — attached to `lane.go`. Minimal:
    - `init`: store `self.yards = 0`.
    - On message `lane.card_played`: increment `self.yards` by 10 (hardcoded for the slice). Post `hud.yards_changed` with the new value.
- `main/ui/hud.gui` — GUI overlay for the match screen:
    - Top bar with "YOU 0 — 0 CPU" text.
    - Center: "YARDS: 0" text, updates on `hud.yards_changed`.
    - Bottom: a single "card" — a box node with the text "TEST CARD" inside, tappable.
    - Top-right corner: a small "MENU" text button to return to menu.
- `main/ui/hud.gui_script` — handles:
    - Tap on test card → post `match.play_test_card` to the match collection's lane.
    - Tap on menu button → post `show_menu` to loader.
    - Listen for `hud.yards_changed` and update the yards text.
- Pre-compute hashes for: `card.play`, `lane.card_played`, `hud.yards_changed`, `match.play_test_card`, `show_menu`, `show_match`, `touch`. Put shared hashes in `main/state/messages.lua` and import.

**Wiring notes:**

- The HUD GUI runs on top of the match collection. The HUD's `gui_script` posts messages to the match collection via URLs like `match:/lane#script`.
- The card factory creates one card on match start. For this slice, the card lives in the lane the entire time and "playing" just increments yards. Real card spawning from hand comes in a later phase.
- Use Defold's `factory.create` to spawn the test card on match init.

**Acceptance criteria for 0.4:**

- Tapping PLAY from menu shows the match screen with HUD overlay.
- The HUD shows "YARDS: 0" initially.
- Tapping the "TEST CARD" button increments yards by 10. After three taps it should show "YARDS: 30".
- Tapping MENU returns to the menu screen.
- Returning to match again resets yards to 0 (because the match collection unloads/reloads).
- No console errors on any transition.

`// === STOP for developer review ===`

---

### Sub-phase 0.5 — Persistence smoke test

Prove save/load works, even with trivial data.

**Files to create:**

- `main/state/save.lua` — module exposing:
    - `M.load()` — returns the current save table or a default if no save exists or decode fails.
    - `M.save(data)` — writes the given table to the save file.
    - `M.get_save_path()` — returns the resolved save path (useful for debugging).
    - Default save table: `{ version = 1, total_taps = 0 }`.
- Update `main/loader.script` to:
    - On init, call `save.load()` and store the result in `self.save_data`.
    - When a match ends (i.e., returning to menu), increment `total_taps` by the yards-gained-this-match and call `save.save(self.save_data)`.
- Update `main/ui/menu.gui_script` to display "TOTAL TAPS: N" below the subtitle, reading from the loader's stored save data via a message.

**Acceptance criteria for 0.5:**

- Fresh launch: menu shows "TOTAL TAPS: 0".
- Play a match, tap test card 3 times, return to menu: shows "TOTAL TAPS: 30".
- Quit the app entirely, relaunch: still shows "TOTAL TAPS: 30".
- Play another match, tap once, return to menu: shows "TOTAL TAPS: 40".
- The save file exists at the path returned by `save.get_save_path()` (which can be logged to the console for verification).

`// === STOP for developer review ===`

---

### Sub-phase 0.6 — CLAUDE.md update

Update `CLAUDE.md` with notes about Phase 0:

- A new section near the bottom titled "## Phase 0 — Vertical slice notes" documenting:
    - What was built in this phase.
    - Any conventions you established beyond what was already in CLAUDE.md (e.g., specific message naming patterns you used, render script quirks, GUI scene loading pattern).
    - Known stub areas that are intentional placeholders for future phases.
- A "## Phase log" section near the top (right after "Project context") tracking which phases have shipped: "Phase 0: complete (vertical slice)".

`// === STOP for developer review ===`

---

## Final acceptance for Phase 0

All of the following must be true before marking the slice complete:

- [ ] Project opens in Defold editor with no errors.
- [ ] Builds and runs on macOS via Defold editor.
- [ ] Menu → Match → Menu flow works end-to-end.
- [ ] Tapping the test card updates the yards counter.
- [ ] Save persists across app launches.
- [ ] Letterbox scaling works correctly on a non-default window size.
- [ ] All hard rules from this prompt and from `CLAUDE.md` were honored.
- [ ] `CLAUDE.md` is updated with Phase 0 notes.
- [ ] No third-party Lua libraries were added.
- [ ] No PNG assets were generated; all visuals use box nodes / built-in text.
- [ ] Total file count is reasonable (under 25 files including configs). If you're approaching 30+ files, you've over-built.

## When you're done

Reply with:

1. A summary of what was built per sub-phase.
2. Any deviations from the prompt and why.
3. Any conventions you established that the developer should know about.
4. Open questions or things you couldn't finish.

Do **not** preemptively start Phase 1 or any port work. After Phase 0, the developer and I (Claude) will design the port phasing together. Phase 1 will come as a separate prompt.
