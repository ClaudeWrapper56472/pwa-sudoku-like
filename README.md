# Nine Lives

A cat-themed logic puzzle built as a Godot 4 reference project: level generation,
difficulty rating by human technique, a full game UI, undo/redo, save state that
survives being killed by iOS, and an export configuration.

Clean-room from published algorithms, no third-party code, no runtime
dependencies. Targets **Godot 4.4+**; developed against 4.7.2.

## The rules

An N×N grid is carved into N irregular colour regions. Place one cat in every
row, every column and every colour — and no two cats may touch, not even
diagonally. Every level has exactly one solution.

Tap a cell to cross it out, or **drag across a row to cross the whole run**.
Crossing out is the bulk of play, so it gets the cheap gesture — and it is free,
a note to yourself that is never checked.

Double-tap to place a cat. That is the committing move and the only one that
costs anything: a cat on the wrong cell is refused and **spends one of three
lives**. Lose all three and you start that same level again — the solution is
never shown, because handing over the answer to a puzzle you are about to retry
would make the retry pointless. Nothing is ever crossed out for you either;
working out what a cat rules out is the game.

Spending a life is fair rather than arbitrary precisely because the solution is
unique. Every wrong cell is one the rules already ruled out, so there is no such
thing as a placement that is only wrong in hindsight.

**There is no difficulty menu.** Level 1 is a gentle 5×5 and every level after it
is a little harder. Finishing one moves you up; losing one does not move you
back.

---

## Running it

```bash
# Play it
/Applications/Godot.app/Contents/MacOS/Godot --path ~/Sites/godot-sudoku

# Open in the editor
/Applications/Godot.app/Contents/MacOS/Godot --path ~/Sites/godot-sudoku -e
```

```bash
cd ~/Sites/godot-sudoku
./run_tests.sh              # 845 assertions, about seven seconds
./run_tests.sh rater        # one suite
./run_smoke.sh              # boots the real game and plays a level to the end
./build_bank.sh 25          # regenerate the precomputed levels
```

The scripts default to `/Applications/Godot.app/Contents/MacOS/Godot`; set
`GODOT=/path/to/godot` to point elsewhere. To look at the game rather than assert
about it, `res://tests/Shot.tscn` boots it in a window and writes PNGs to
`user://shots`.

**Keyboard:** arrows move, `Space`/`X` crosses out, `Enter`/`C` places a cat,
`Backspace` clears, `H` hints, `Cmd`/`Ctrl`+`Z` undoes. Right-click is the mouse
shorthand for a double-tap.

---

## Layout

```
project.godot            Autoloads, display setup, GL Compatibility renderer
export_presets.cfg       iOS and macOS presets

scenes/
  Main.tscn              Root; screen routing
  MenuScreen.tscn        Difficulty picker, Continue, stats, options
  GameScreen.tscn        Board, toolbar, result and loading overlays
  Board.tscn             The grid
  Cell.tscn              One square: colour, cross or cat

scripts/puzzle/          Pure puzzle logic. Nothing here extends Node, so the
						 whole layer runs headless in tests.
  cat_grid.gd            Geometry, bitmask helpers, the rules themselves
  cat_level.gd           One level: size, regions, solution
  solver.gd              Row-by-row search, solution counting, rival finding
  generator.gd           Placement, region carving, uniqueness repair
  rater.gd               Technique-by-technique logical solver
  level_ladder.gd        Level number -> which board to generate
  level_bank.gd          Reads precomputed levels from content/

scripts/commands/        Undo system
  command.gd             Base class
  set_mark_command.gd    Change one cell
  cross_run_command.gd   One drag across a run of cells
  undo_stack.gd          Two stacks, serialization, command factory

scripts/
  game_state.gd          Autoload: the running game, all signals
  settings.gd            Autoload: preferences, user://settings.cfg
  save_manager.gd        Autoload: user://sudoku_save.json, suspend hooks
  save_migration.gd      Pure version-migration functions
  puzzle_state.gd        The board model commands act on
  ui/
	palette.gd           Every colour used by procedural drawing
	cat_art.gd           All cat and paw drawing, as static functions
	cat_mascot.gd        The sitting cat on the menu and result card
	lives_display.gd     The row of hearts
	paw_backdrop.gd      Faint paw prints behind the menu
	square_slot.gd       Keeps the board square inside a VBoxContainer
	cell.gd, board.gd, main.gd, menu_screen.gd, game_screen.gd

resources/cat_theme.tres Widget chrome: buttons, panels, label colours
tests/                   Unit suites, the smoke test, the screenshot helper
tools/                   Content build step for the level bank
content/                 Generated level bank (data, not code)
```

---

## The puzzle layer

### A solution is a permutation

Exactly one cat per row means a whole solution is a list of columns indexed by
row. Everything follows from that:

- **Search has no cell-selection heuristic.** Walk the rows in order; each must
  be filled exactly once.
- **Used columns and used regions are bitmasks**, carried down the recursion.
- **The no-touching rule collapses.** Two cats more than one row apart can never
  touch, so adjacency is only ever "the next row's column must differ by more
  than one" — a three-bit mask, not a 2D neighbourhood check.

`CatSolver.count_solutions` takes a limit and stops there. Uniqueness checks pass
2, so the search abandons a level the moment it finds a second answer.

### Generation runs backwards from Sudoku

A Sudoku generator starts from a filled board and removes clues. This puzzle has
no clues to remove — **the regions are the puzzle**. So generation goes the other
way:

1. Draw a random legal placement: one cat per row and column, none touching.
2. Seed one region on each cat and grow all N regions outward until they
   partition the board. Every region then holds exactly one cat by construction,
   so the placement is guaranteed to be *a* solution.
3. Make it the *only* solution.
4. Rate it, and reject if the rating misses the requested tier.

**Step 2 is where the first version failed.** Growth originally always extended
the smallest region, which produced beautifully balanced blobs — and terrible
puzzles. Measured over 40 boards per size, **zero** had a unique solution; most
had six or more. Fat, even regions barely constrain anything.

Growing from a random *frontier cell* instead means a region with more edge grows
faster, so sizes come out uneven — one colour squeezed into two cells, another
sprawling across a dozen. That is what constrains: a small region forces a
placement almost immediately, and it cascades. Same code path, one line
different, and uniqueness went from 0% to 25–85% depending on board size.

**Step 3 is a targeted repair, not a retry.** Blind regrowth wastes the work.
There is a move available instead: ask the solver for a *rival* placement, take
any row where it disagrees with ours, and look at the cell its cat occupies
there. Re-colour that one cell to any neighbouring colour and the rival instantly
uses that colour twice, so it dies. Our own placement is untouched, because the
cell moved is never one of our cats.

Each pass kills at least the rival it was shown. New rivals can appear, so it
loops — but it converges in a handful of passes where blind regrowth took
hundreds of attempts.

### The ladder

There is no difficulty picker, so something has to decide what level 7 looks
like. `level_ladder.gd` is that.

Difficulty climbs on two axes. The board grows, and within each size the required
techniques ramp Easy to Expert — so the curve rises steadily and dips slightly
whenever the board grows, which is the breather that pays for the extra rows and
columns.

**Each size lasts longer than the one before it.** A 5×5 is understood in a few
goes; a 9×9 deserves thirty.

| Board | Levels | |
|---|---|---|
| 5×5 | 1–10 | 10 levels |
| 6×6 | 11–25 | 15 |
| 7×7 | 26–45 | 20 |
| 8×8 | 46–69 | 24 |
| 9×9 | 70–99 | 30 |
| 10×10 | 100 onward | forever |

Past level 129 the board and the tier stay put, but the level number keeps
climbing. You never hit a wall; you just stop getting bigger boards.

### Why the boards stop at 10×10

Three separate ceilings, and the measured one is not the one you would guess.

**Generation cost grows about five-fold per extra row.** Region carving admits
astronomically many solutions on a large board, and the repair loop kills rivals
one at a time:

| Size | Per attempt | Unique-solution rate |
|---|---|---|
| 9×9 | 8 ms | ~8% |
| 10×10 | 34 ms | ~8% |
| 11×11 | 129 ms | ~17% |
| 12×12 | 1.75 s | nothing in six tries |

**Touch targets shrink faster than they look.** On a 720-unit viewport at iPhone
scale, a 9×9 cell is 41 pt and a 12×12 cell is 30 pt, against Apple's 44 pt
guidance. Double-tapping a 30 pt cell to commit a move that costs a life is not a
reasonable ask.

**And every region needs its own colour.** Past a dozen flat colours nobody can
tell them apart at cell size — a limit of eyes, not code. The tenth colour is a
neutral stone precisely because every other hue family was already taken.

Going meaningfully further would mean replacing grow-then-repair with a
construction that keeps regions constraining as they scale. The colour ceiling
would still stop it around twelve.

### Difficulty is rated, not assumed

Board size is a bad difficulty measure on its own: a 9×9 can fall to nothing but
"last cell standing", and a 6×6 can need real work. So `rater.gd` is a second,
deliberately weak solver that never guesses. Each pass it applies the *cheapest*
technique that fires and records the hardest it ever needed. Cheapest-first is
the whole point — a solver allowed to reach for the expensive techniques early
would rate every level Expert.

The key simplification: **rows, columns and colours are all just groups of cells
that must contain exactly one cat.** Almost every technique is written once
against that idea and applied to each pair of group kinds, which is why the
ladder is four rungs rather than a dozen near-duplicates.

| Tier | Adds |
|---|---|
| Easy | **Last one standing** — a row, column or colour with one candidate left |
| Medium | **Penned in** — a group whose candidates all fall inside one other group clears the rest of that group |
| Hard | **Too close** — a cell that every candidate of some group would touch |
| Expert | **Locked group** — k groups penned into k groups lock each other out |

"Penned in" is one rule applied six ways: a colour penned into a row, a row
penned into a colour, a colour penned into a column, and so on. "Locked group" is
the same rule for k = 2 and 3.

If the rater stalls before the board is full, the level needs something outside
this set and the generator rejects it. That rejection is what makes the tier claim
honest, and the suite checks it in both directions: a level rated tier N solves
with N's cap, and does *not* solve with tier N−1's cap.

### Measured behaviour

Generation cost per tier (8 samples, headless, Apple silicon):

| Tier | Board | Attempts | Time |
|---|---|---|---|
| Easy | 5×5–6×6 | 7.0 | 21 ms |
| Medium | 6×6–7×7 | 3.6 | 25 ms |
| Hard | 7×7–8×8 | 1.8 | 51 ms |
| Expert | 8×8–9×9 | 5.2 | 379 ms |

Easy takes *more* attempts than Hard, which looks wrong until you think about it:
a randomly carved board is usually harder than Easy, so the loop keeps rejecting
until it draws a gentle one. Difficulty is not something the generator aims at —
it is something it filters for.

### No repeats

Every level carries a fingerprint — its board size and region string, hashed —
and the save remembers what has been served. The bank filters those out before
drawing, and the generator rejects a match and keeps looking.

**Only the current board size is remembered.** The ladder never sends a player
back to a smaller board, so the moment the size goes up every fingerprint below
it describes a board that can no longer occur. Keeping them would be paying save
space and lookup cost forever for a collision that is impossible by construction.
Recording a board at a new size therefore throws the previous size's list away
wholesale.

That also means the cap on the list rarely matters. Sizes 5 through 8 each span
at most six levels before the ladder moves on; only size 9, which the ladder
stays on for good, accumulates enough to reach it.

Two details keep it honest. The fingerprint is hashed rather than stored whole,
because full region strings would bloat the save for no benefit and a collision
costs exactly one skipped puzzle. And the set is rebuilt from the saved array on
every read: JSON turns each number into a float on the way back in, so comparing
an int against them would silently never match and the whole mechanism would
quietly do nothing while looking correct.

The generator will repeat a board rather than fail to produce one. If every
attempt at the right tier has been seen, the first is returned anyway — a repeat
is a small annoyance, no level at all is a broken game.

### The level bank

Runtime generation is fast enough here, but it is uneven and it is a rejection
loop. So `tools/build_level_bank.gd` generates levels on a build machine into
`content/level_bank.json`, and `LevelBank.take()` serves one instantly. Eighty
levels take about eight seconds to build and a few kilobytes to store.

That trade — cheap to store, expensive to find — is why puzzle apps ship large
content archives next to small code.

The bank is never required. With no bank file the game generates at runtime, and
an explicit seed always generates, so reproducing a level by seed keeps working.
Entries are verified on the way out: a corrupt or hand-edited bank is rejected
and the game falls back to generating. It also declines rather than repeat once
everything matching has been served, which with twenty levels per tier happens
sooner than it sounds.

### Seeding

One `RandomNumberGenerator`, seeded once, drives the whole loop: the placement,
the region growth, the repair. The same `(tier, seed)` always produces the
identical level, including how many attempts it took. `Array.shuffle()` is never
used because it draws from the global generator and would break that.

---

## The game layer

### Signals, not node paths

Three autoloads: **`Settings`** (preferences), **`SaveManager`** (the save
document and the suspend hooks), **`GameState`** (the running game and every
signal the UI listens to).

Nothing reaches into another scene's node tree. The board listens to
`GameState.cells_changed` and repaints; the top bar listens to `time_changed`,
`mistakes_changed` and `cats_changed`. Input travels the other way as signals
too: a cell emits `tapped`, the board re-emits `cell_tapped`, and the game screen
— the one script that knows every piece exists — connects it to `GameState`.

The payoff is that `Board.tscn` has no idea a toolbar exists and can be dropped
into a test scene on its own. `SaveManager` goes further and does not know
`GameState` exists at all: it announces `save_requested`, whoever owns live state
hands it over, and the write happens.

### The undo system

Undo is a command pattern: each move is an object that knows how to apply itself
and how to put things back. There are two kinds, and the difference between them
is the interesting part.

`SetMarkCommand` changes one cell. `CrossRunCommand` is one drag across a run of
cells, and it exists because **one gesture is one decision** — having to press
undo nine times to take back one swipe would be absurd.

A drag also inverts the usual order. Cells are applied as the finger passes over
them, so the player sees each one change immediately, which means the run is
already on the board by the time the gesture ends. `UndoStack.push_applied()`
files a command without re-applying it. Re-applying would be harmless here but
dishonest, and it would fire a second change signal for a move the board has
already drawn.

Two rules the drag depends on: the target mark is fixed when the drag *starts*
(from an empty cell it crosses out, from a crossed cell it erases), which is what
stops cells flickering on and off as the finger wanders back over its own path;
and a drag never touches cats, because a gesture this easy to aim carelessly
should not undo a deliberate placement.

Snapshots would also work — the board is at most 81 bytes. Commands still win:
they serialize to a handful of integers so undo history goes into the save file,
redo is free, and the board is told which cells to repaint.

One more rule: a new move drops the redo stack, and **undo never rewinds a loss**.
Running out of lives locks the board, and undoing your way back out would make
the lives meaningless. The smoke test checks that.

### Save state

`user://sudoku_save.json`, one document with two halves:

```jsonc
{
  "version": 4,
  "session": {
	"tier": 2, "seed": 12156,
	"board": {
	  "level": {
		"size": 4,
		"regions": "ABCBABBBAADBADDB",  // one letter per cell
		"columns": "2031"                // solution: column per row
	  },
	  "marks": ".x..c..........."         // . empty, x cross, c cat
	},
	"level": 7, "elapsed": 412.5, "lives": 2, "hints": 1,
	"selected": 34,
	"history": { "undo": [...], "redo": [...] }
  },
  "stats": {
	"tiers": { "0": { "started": 5, "won": 4, "best_time": 220,
					  "total_time": 900, "mistakes": 3 } },
	"streak": { "current": 3, "best": 7 },
	"progress": { "level": 7, "completed": 6 },
	"hints_used": 12
  }
}
```

**Surviving suspend.** Mobile platforms give no warning before the process is
killed, so every hook that might be the last one writes the file:
`NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_APPLICATION_FOCUS_OUT`,
`NOTIFICATION_WM_CLOSE_REQUEST`, `NOTIFICATION_WM_GO_BACK_REQUEST` and
`NOTIFICATION_EXIT_TREE`. `SaveManager` runs with `PROCESS_MODE_ALWAYS` so a save
triggered by a pause still runs.

**Atomic writes.** The document goes to a temp file and is then renamed over the
real one. Rename within a filesystem is atomic, so a process killed mid-save
leaves either the old file or the new one, never half of one — which matters
because the most likely moment to be killed is exactly while saving.

**Versioning.** `save_migration.gd` is pure functions with no file access, so
migration is unit tested without touching `user://`.

| Version | Change |
|---|---|
| 1 | Flat document. Marks as integers, difficulty as a display name, stats keyed by that name. |
| 2 | Session and stats separated; marks as one character per cell; adds undo history, hints and the streak. |
| 3 | A wrong cat ends the level, and placing one no longer crosses out cells. Commands are single-cell. |
| 4 | One climbing progression instead of a difficulty menu. Stats gain a progress block; the session records its level. |

Migration steps forward one version at a time, and each step is a public function
so it can be tested on its own — the chain is only as trustworthy as its weakest
link, and testing only the whole chain hides which link broke.

Two of the steps changed the *rules*, not just the shape, and both had to decide
what to throw away:

- **v2 → v3.** A v2 board could legitimately hold a cat on a wrong cell; under v3
  it cannot. The migration keeps the crosses — still the player's own reasoning —
  lifts wrong cats, and **drops the undo history**. Those commands were recorded
  against the old rules, and reverting one could reconstruct a board the new rules
  would never produce.
- **v3 → v4.** A v3 session was a one-off puzzle at a chosen difficulty, with no
  level number and no honest way to give it one. It is dropped. Stats survive, and
  the level to resume on is derived from total wins — which can only ever be
  generous, never punishing, and that is the right direction to be wrong in.
  Resuming an 8×8 Expert under a header reading "Level 6 · Medium 6×6" would look
  like a bug, and losing one unfinished puzzle is the smaller cost.

A document with no version, or a version newer than this build, is discarded
rather than guessed at — a newer save may use fields we would silently drop.

---

## The look

Every cat, paw print, cross and cell is drawn in code. There is not a single
image file in the project apart from the app icon.

That is a deliberate trade. It stays sharp at any size — a cat in a 30-pixel cell
of a 9×9 and the same cat at 128 pixels on the menu are one function with a
different rect, so there are no `@2x`/`@3x` sets to maintain. Restyling is
editing a colour table rather than re-exporting a sprite sheet. The cost is that
procedural art can only be as good as its primitives, which for a cat made of six
circles and two triangles is fine.

The menu mascot cycles through nine breeds, separated on three axes at once — fur
colour, a marking, and an expression — because colour alone fails a colourblind
player and fails anyway at small sizes where two mid-tone greys converge.

**Colour is load-bearing here in a way it is not in Sudoku.** An early version
dimmed the selected cell's row, column and colour, the way a Sudoku highlights
peers. It had to go: in this game the region *is* its colour, so two shades of
the same blue read as two different regions. Selection is an outline instead.

Spent lives stay on screen as hollow hearts rather than disappearing. A row that
shrinks tells you how many you have; a row that hollows out tells you how many
you have *left of how many*, which is the number that matters when you are
deciding whether to risk a guess.

Two systems split the colour work by what each can express. `palette.gd` holds
everything used by procedural drawing, because a `Theme` cannot say "this cell
belongs to region 4". `resources/cat_theme.tres` holds widget chrome — button
styleboxes, focus rings, label colours — which is exactly what a `Theme` is for.
The menu's option rows are toggle `Button`s rather than `CheckButton`s because
the default check icons are near-white and would vanish against warm paper, and a
texture cannot be recoloured from a Theme.

---

## Testing

```
test_solver.gd      the rules, solving, counting, the tutorial board
test_generator.gd   legality, uniqueness, region shape, seed reproducibility
test_rater.gd       tier assignment in both directions, hints
test_commands.gd    undo/redo, wrong-cat detection, serialization, depth cap
test_save.gd        v1 migration, normalization, JSON round trips
test_bank.gd        every shipped level is legal, unique and correctly rated
test_ladder.gd      what board each level number asks for
smoke.gd            boots the real game and plays levels to a win and a loss
```

Plain assertions rather than GUT, so the suite runs with nothing installed.
Roughly a thousand assertions in about seven seconds, plus 47 end-to-end checks
covering a drag, a win, running out of lives, retrying, and the fingerprint
pruning that happens when the board grows.

The solver suite uses the four-by-four tutorial board as its fixture, and one
test on it is worth calling out. The placement `[2, 3, 0, 1]` satisfies
one-per-row, one-per-column and one-per-colour perfectly — it is excluded *only*
because two of its cats would touch diagonally. Without the no-touching rule that
board would have two answers. The test asserts each of those facts separately, so
if anyone ever "simplifies" adjacency out of the solver, it fails loudly.

**One Godot quirk worth knowing.** Both harnesses run as *scenes*
(`res://tests/TestRunner.tscn`), not with `--script`. Godot only registers
autoload singletons when it boots a scene — under `--script`, any script that
mentions `GameState` or `Settings` fails to compile with "Identifier not found",
which would rule out testing anything above the puzzle layer.

---

## Exporting

### Producing a .pck

A Godot game is two artefacts: the **engine binary**, identical for every game
built with that engine version and feature set, and the **`.pck`**, your scenes,
scripts and data packed into one archive. To produce content alone:

```bash
godot --headless --path . --export-pack "iOS" build/nine-lives.pck
```

At runtime the engine mounts the `.pck` over `res://`, which is why nothing in
this project cares whether it is running from source or from a pack.

### Why the split matters for update size

The engine binary is tens of megabytes and changes only when you upgrade Godot.
The content archive is everything you actually iterate on. Keeping them separate
means smaller updates (iOS ships changed blocks, and content-only changes leave
the large, stable binary alone), and it means content can ship as data —
`ProjectSettings.load_resource_pack()` mounts an additional `.pck` at runtime, so
new level banks or themes need no rebuild. App Store rules still govern what you
may download and when.

The level bank in `content/` is the concrete case: it is data, it ends up in the
`.pck` and never in the binary, and rebuilding it changes one file. That is also
why an ad or analytics SDK is expensive — it links into the binary side, growing
the artefact that is otherwise stable across releases.

### Running it on an iPhone

Every step below was worked out the hard way against Xcode 26.6 and iOS 26.6.1.
The failure modes are unhelpful — Godot reports most of them as
`Failed to run xcodebuild with code 0`, with the real reason swallowed.

**1. Export templates.** Editor > Manage Export Templates > Download and Install.
They must match the engine version exactly.

**2. The iOS platform component.** Xcode 26 downloads platforms on demand, and
without it every build fails with:

```
error: iOS 26.5 is not installed.
	   Please download and install the platform from Xcode > Settings > Components.
```

This one is genuinely misleading: `xcodebuild -showsdks` lists the SDK and
`Platforms/iPhoneOS.platform` exists, because only the *stub* ships with Xcode.

```bash
xcodebuild -downloadPlatform iOS   # ~8.5 GB
```

**3. A Team ID — which you cannot look up.** `application/app_store_team_id`
wants a 10-character identifier like `A1B2C3D4E5`. An email address is silently
accepted by the config and rejected by `xcodebuild`.

On a **free** Apple ID there is nowhere to read it: the Devices and Membership
pages at developer.apple.com are paid-only, and Xcode's Accounts pane does not
show it for a personal team. It does not exist until a signing certificate does.
So put a placeholder in, let Xcode create the certificate, then read it back:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
# the Team ID is the OU= field
```

**4. Export an Xcode project, not an `.ipa`.** An `.ipa` target makes Godot shell
out to `xcodebuild` to archive and sign, which fails opaquely if anything about
signing is wrong. An `.xcodeproj` target lets Xcode handle signing and gives you
a Run button. `export_presets.cfg` is set up this way.

**Godot does not create the target folder**, so create it first:

```bash
mkdir -p build/ios
godot --headless --path . --export-debug "iOS" build/ios/NineLives.xcodeproj
open build/ios/NineLives.xcodeproj
```

**5. Register the device by connecting it.** A free team's provisioning profile
needs a device, and you cannot add one through the developer portal. Xcode
registers it automatically — but only while the phone is genuinely reachable. If
it is not, you get:

```
Your team has no devices from which to generate a provisioning profile.
```

Connect by **data** cable, unlock, tap Trust, and enable
**Settings > Privacy & Security > Developer Mode** (required on iOS 16+, needs a
reboot). Then check the state really is `connected`:

```bash
xcrun devicectl list devices
```

**6. Sign and run.** In Xcode: the `NineLives` target > Signing & Capabilities >
tick *Automatically manage signing* > pick your team by name. That is the moment
the certificate and provisioning profile are created. Then Cmd-R.

**7. Trust the certificate on the phone.** The first launch is refused with
*"invalid code signature, inadequate entitlements or its profile has not been
explicitly trusted"*. On the device: **Settings > General > VPN & Device
Management** > your developer certificate > **Trust**.

Free-team profiles expire after **7 days**, so expect to repeat the export and
run weekly.

### What the preset already handles

These are real App Store requirements, and they are set up in
`export_presets.cfg` so they do not become surprises at upload time:

- **Bundle identifier** — reverse-DNS and unique to you. Change
  `application/bundle_identifier` to your own; two people cannot ship the same
  one.
- **Architecture** — `architectures/arm64=true`. Every supported iOS device is
  arm64 and there is nothing else to enable.
- **Icons** — all 53 `icons/*` slots are deliberately **empty**. Godot generates
  every size from `application/config/icon`, scaled by
  `application/icon_interpolation`. Fill an individual slot only if you want
  different art at that size. The source must be **1024x1024 with no alpha
  channel** — not merely opaque, absent; a fully-opaque alpha channel still fails
  validation, and flattening a transparent PNG leaves one behind unless you also
  convert to RGB.
- **Launch screen** — `storyboard/use_launch_screen_storyboard=true`. A
  storyboard is required; a static image is not accepted. This one uses a solid
  colour matching the boot splash.
- **Minimum iOS version** — `application/min_ios_version`, 14.0 here.
- **Privacy manifest** — the `privacy/collected_data/*` block. Collecting nothing
  still has to be declared, and this game collects nothing.

### Two things that will waste your afternoon

**The Godot editor owns `export_presets.cfg`.** While the editor is open it
rewrites that file from its own in-memory state, so edits made in a text editor
are silently reverted. Change export settings in the editor's own dialog, or with
the editor closed.

**Do not commit the export output.** It lands wherever `export_path` points, and
the engine xcframework is around 400 MB — two files inside it are over GitHub's
100 MB per-file limit, so a push is rejected outright. `.gitignore` covers
`*.xcframework/`, `*.xcodeproj/` and the generated target directory, but if the
export ever writes somewhere unexpected, check `git status` before committing.

For reference, a debug build splits like this:

| Artefact | Size |
|---|---|
| `NineLives.pck` — every scene, script, level and image | ~320 KB |
| `NineLives.xcframework` — the engine | ~409 MB |

### Renderer

`project.godot` selects **GL Compatibility**, which targets OpenGL ES 3.0 on iOS.
For a 2D game drawing rounded rectangles and cats there is no reason to pay for
Forward+, and Compatibility runs on far more hardware.

---

## Deliberate omissions

- **No sound, no animation.** The cats are static; a blink or an ear twitch would
  be a `_process` tick and a `queue_redraw()`.
- **No tutorial.** The rules fit in one line, which the game screen shows on load.
- **No collection, currency or shop.** The save format is versioned, so adding
  them is a v5 migration rather than a rewrite.
- **No level select.** You are on a level; you play that level. Jumping around
  would make the ladder decorative.
- **The rater stops at locked groups.** Deeper chain reasoning would let the
  generator accept levels it currently rejects. Each technique added to
  `_apply_cheapest` in ladder order automatically widens what qualifies.
