# Claude Code Prompt — Phase 0 Fix-up: Revert Custom Render Script

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** If anything in this prompt conflicts with it, surface the conflict and stop.

## Context

During Phase 0 development, a custom render script (`render/gridiron.render_script`) was added in sub-phase 0.2 to implement fit-to-shortest-axis letterboxing for portrait 1170×2532. After completion, testing revealed that `gui.pick_node` was returning false for taps on visible GUI buttons — the menu's PLAY button and the HUD's TEST CARD and MENU buttons all failed to register taps reliably.

Diagnosis: the custom render script's combination of letterboxed viewport + design-resolution projection broke Defold's GUI input coordinate transform. `action.x/y` ended up in a coordinate space that didn't match `gui.pick_node`'s expectations, so picking failed even though rendering looked correct.

**Resolution: revert to Defold's built-in default render script.** This restores correct GUI input behavior and is what `CLAUDE.md` originally said to do anyway (the original CLAUDE.md says: *"Don't write a custom render script unless we hit a specific limitation. Start with the default and our minimal scaling override. Custom render scripts are a debugging black hole."*) The custom render script violated that rule prematurely.

The developer has already manually changed `game.project`'s `[bootstrap] render` entry to `/builtins/render/default.renderc` and verified that all buttons now work. This prompt cleans up the dead files and locks the fix in.

## Hard rules

1. **Confirm `game.project` already uses `/builtins/render/default.renderc`.** If for some reason it doesn't, set it. Do not introduce a different render script.
2. **Delete the dead custom render files.** They're no longer referenced; leaving them in confuses future work.
3. **Update CLAUDE.md to reflect the lesson.** Specifically:
    - Remove or strike through any references to `render/gridiron.render_script` and `render/gridiron.render` in the file layout section.
    - Add a "Phase 0.6.5 — Render script lesson learned" note to the Phase 0 section of CLAUDE.md documenting what happened and why future custom render scripts need to be tested against `gui.pick_node` before being committed.
    - Add a hard rule somewhere appropriate: "Custom render scripts must verify `gui.pick_node` works correctly for taps on visible GUI nodes before being merged. This is a known footgun."
4. **Add a Phase log entry.** Note that Phase 0 had a fix-up and what was changed.
5. **Do NOT add letterboxing back in any form.** Default render's auto-stretching for non-matching aspect ratios is acceptable for v1. Letterboxing will be revisited post-TestFlight when we have real-device data.
6. **Do NOT start Phase 1.** Stop after the fix-up is complete.

## Tasks

### Task 1: Verify and lock in `game.project`

- Open `game.project`.
- Confirm the line under `[bootstrap]` reads exactly: `render = /builtins/render/default.renderc`
- If it doesn't, set it.

### Task 2: Delete dead custom render files

Remove these files from the repo (they're no longer referenced):

- `render/gridiron.render_script`
- `render/gridiron.render`

If the `render/` directory is now empty, leave it with a `.gitkeep` (per the established convention for empty folders).

### Task 3: Update CLAUDE.md

In CLAUDE.md, make these edits:

**3a.** In the file layout section (the `gridiron-tactics-defold/` tree near the top), remove the `render/gridiron.render_script` line. The `render/` folder line itself can stay (with a comment that it's reserved for future use) or be removed entirely — your call as long as it's accurate.

**3b.** Add a new hard rule to the "## Hard rules" section. Number it sequentially. Suggested wording:

> **N. Custom render scripts are a known footgun.** Use `/builtins/render/default.renderc` unless we have a specific, tested reason to customize. Any custom render script must verify that `gui.pick_node` correctly registers taps on visible GUI buttons before being merged. The Phase 0 letterbox attempt broke input picking even though rendering looked correct.

**3c.** Add a "Phase 0.6.5 — Render script lesson learned" section to the bottom of the existing Phase 0 notes section. Document:

- The custom render script (gridiron.render_script) implemented fit-to-shortest-axis letterboxing
- It broke `gui.pick_node` because the custom projection + viewport combination didn't align with Defold's input coordinate transform
- Reverted to default render; all GUI buttons now work
- Letterboxing deferred to a post-TestFlight phase when real-device aspect ratio behavior can be evaluated
- Default render's auto-scaling is acceptable for v1 across iPhone 11+ (which are all within ~5% of design aspect ratio)

**3d.** In the Phase log section (top of CLAUDE.md):

- Add a "Phase 0.6.5: complete (render script fix-up — reverted to default render)" entry below the existing Phase 0 entry.

### Task 4: Re-verify Phase 0 acceptance

Run through the Phase 0 acceptance criteria mentally and confirm they all still pass with the default render:

- [ ] Project opens in Defold editor with no errors
- [ ] Menu → Match → Menu flow works
- [ ] PLAY button on menu registers taps reliably
- [ ] TEST CARD button registers taps reliably
- [ ] MENU button on HUD registers taps reliably
- [ ] Tapping TEST CARD increments yards counter
- [ ] Save persists across app launches
- [ ] No console errors

If you have access to run the project and any of these fail, surface the failure. Do not silently assume they pass.

### Task 5: Report back

Reply with:

1. Confirmation that `game.project` uses default render.
2. List of files deleted.
3. Summary of CLAUDE.md edits made.
4. Any deviations or concerns.

## When you're done

Stop. Do not start Phase 1.
