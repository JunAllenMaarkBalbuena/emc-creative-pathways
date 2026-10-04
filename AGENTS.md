# AGENTS.md

Instructions for AI agents working in this project.

## Project

Godot **4.7**, GL Compatibility renderer, **GDScript only** (no C# in the tree).
Viewport 1280x720, `canvas_items` stretch, `expand` aspect.
Autoloads: `LevelProgression`, `SettingsManager`, `SceneTransition`, plus `_mcp_game_helper`
(from the `godot_ai` addon).

Keep code GDScript. Do not introduce C#.

## Godot skills

This project has **110 Godot domain skills** available, covering project setup, architecture,
gameplay systems, UI, physics, shaders, multiplayer, testing and export. They are vendored from
three upstreams into `vendor/godot-skills/` (gitignored):

- `godot-prompter/` - jame581/GodotPrompter, 55 skills
- `modastar/` - @modastar/godot-skills, 14 skills
- `gd-agentic/` - thedivergentai/GD-Agentic-Skills, 41 of its 99 skills

The third source is curated, not vendored wholesale. The `$GD_AGENTIC_INCLUDE` allowlist in
`tools/setup-godot-skills.ps1` records what was kept and why; the ~35 skills it ships that
re-cover topics the other two already have under different names (`godot-tweening` vs
`godot-tween`, `godot-ui-theming` vs `godot-ui`, `godot-state-machine-advanced` vs
`state-machine`, ...) are deliberately left out. What it contributes is genre design, which
nothing else covers, plus a handful of systems that had no equivalent.

Load them with OpenCode's `skill` tool using the **bare skill name**, e.g. `skill({ id: "state-machine" })`.
There is no `godot-prompter:` prefix; these are registered as ordinary skills.

To refresh them after an upstream release:

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup-godot-skills.ps1
```

That script is also what applies collision policy, so run it rather than adding skills by hand:

1. A skill in `.agents/skills/` wins over anything vendored. `godot-debugging` is this project's
   own; the upstream copy of that name is deliberately not vendored.
2. Between the upstreams, `godot-prompter` wins. Its `godot-ui` is vendored; the modastar
   one is not.
3. `gd-agentic` goes last, so it also loses any future name collision.

### Rule: invoke the matching skill before implementing

Before writing any Godot system code, load the relevant domain skill. This applies to subagents
writing Godot code too.

| Situation | Load first |
|---|---|
| New system, or requirements unclear | `godot-grill` - settle decisions first, then design |
| Known change, explicit ask, bug fix | the matching domain skill |
| Movement, input, cameras | `player-controller`, `input-handling`, `camera-system` |
| Architecture | `state-machine`, `event-bus`, `scene-organization`, `component-system`, `resource-pattern`, `dependency-injection` |
| Gameplay systems | `inventory-system`, `dialogue-system`, `ability-system`, `save-load` |
| Enemy AI | `ai-navigation` |
| UI, HUD, i18n | `godot-ui`, `hud-system`, `responsive-ui`, `localization` |
| Animation, tweens, audio | `animation-system`, `tween-animation`, `audio-system` |
| Physics, 2D, 3D | `physics-system`, `2d-essentials`, `3d-essentials` |
| Shaders, VFX, procgen, math | `shader-basics`, `particles-vfx`, `procedural-generation`, `math-essentials` |
| Multiplayer | `multiplayer-basics`, `multiplayer-sync`, `dedicated-server` |
| Mobile, XR, native, threads | `mobile-development`, `xr-development`, `gdextension`, `multithreading` |
| Editor tools, assets | `addon-development`, `assets-pipeline` |
| GDScript idioms | `gdscript-patterns`, `gdscript-advanced` |
| Test, debug, profile, review | `godot-testing`, `godot-debugging`, `godot-optimization`, `godot-code-review` |
| Setup, design, export | `godot-project-setup`, `godot-brainstorming`, `export-pipeline` |
| Teaching while building | `godot-mentor` |
| Genre design | `godot-genre-<genre>` - 27 available: `platformer`, `metroidvania`, `roguelike`, `rts`, `tower-defense`, `visual-novel`, `shooter`, `shooter-fps`, `card-game`, `fighting`, `action-rpg`, `survival`, `stealth`, `puzzle`, `racing`, `rhythm`, `horror`, `idle-clicker`, `simulation`, `sandbox`, `open-world`, `moba`, `battle-royale`, `party`, `sports`, `romance`, `educational` |
| Combat / progression / economy | `godot-combat-system`, `godot-rpg-stats`, `godot-turn-system`, `godot-economy-system`, `godot-quest-system` |
| Death, respawn, secrets | `godot-mechanic-revival`, `godot-mechanic-secrets` |
| Second opinion on architecture | `godot-analyst`, `godot-auditor`, `godot-builder` |
| Balance auditing | `godot-monte-carlo-balancer` |
| Screenshots of the running game | `godot-agent-vision` |
| Upgrading the engine version | `godot-version-migration` |

### `godot-master` is not the entry point

Its own description claims to be the *"Primary entry point for ALL Godot development tasks"* and
it routes to 92 sibling skills. The routing table above wins:

- Load it for its architecture frameworks, anti-pattern catalog or performance budgets as one
  reference - typically a greenfield design or a performance investigation - not as a reflex
  before every task. The per-topic skills are more specific and cheaper to load.
- Two entry points means ambiguous routing, so choose deliberately: a table row for a known
  topic, `godot-master` only for cross-cutting architecture or performance work.

`gd-agentic` skills cross-reference their absent siblings two different ways, and the two need
different handling:

- **"Related Skills" links are absolute GitHub URLs.** They will not fail; they just send you off
  to the web for content you usually have locally. Prefer the local equivalent.
- **"Skill Chain" tables use bare skill IDs that are not installed.** These *will* fail to load.
  The seven most-cited, with their substitutes:

  | Referenced but absent | Load this instead |
  |---|---|
  | `godot-save-load-systems` | `save-load` |
  | `godot-state-machine-advanced` | `state-machine` |
  | `godot-camera-systems` | `camera-system` |
  | `godot-navigation-pathfinding` | `godot-navigation` or `ai-navigation` |
  | `godot-input-handling` | `input-handling` |
  | `godot-inventory-system` | `inventory-system` |
  | `godot-ui-containers` | `godot-ui` |

  For the remaining 24, and for the deliberately excluded names, read
  `docs/gd-agentic-skill-map.md`. Every substitute is verified to exist. When a name is absent
  and unmapped, use the local skill for that topic rather than trying the name as written.

`godot-debugging` is cited twice by godot-prompter and resolves normally - to this project's own
`.agents/skills/godot-debugging`, which sits outside `vendor/`. Nothing to substitute.

### Near-neighbour pairs

Seven modastar skills sit on the same topic as a godot-prompter skill under a different name.
They are not duplicates, they differ in depth. Pick deliberately:

| Terse (modastar) | Full (godot-prompter) |
|---|---|
| `godot-gdscript` | `gdscript-patterns`, `gdscript-advanced` |
| `godot-gdshader` | `shader-basics` |
| `godot-tween` | `tween-animation` |
| `godot-input` | `input-handling` |
| `godot-navigation` | `ai-navigation` |
| `godot-character-body` | `player-controller` |
| `godot-localization` | `localization` |

Default to the full skill; use the terse one for a quick API confirmation. The other seven
modastar skills have no neighbour and are unique: `godot-docs-lookup`, `godot-tilemap-2d`,
`godot-mesh-lod-3d`, `godot-multimesh-3d`, `godot-occlusion-culling-3d`,
`godot-visibility-ranges-3d`, `godot-pipeline-compilation`.

Then report before you build: name the pattern you chose, the alternative you rejected, and why.
Skills carry trade-offs - surface them. The choice belongs to the developer.

Rationalising is a signal you skipped the skill:

| Thought | Reality |
|---|---|
| "I know how CharacterBody2D works" | Knowing the class is not knowing the pattern. Load the skill. |
| "It's a two-line script" | Two-line scripts still pick node types. Load the skill. |
| "I loaded a Godot skill already" | Different system, different skill. |
| "The user wants a quick fix" | Quick fixes set architecture. Load it, then say what you picked. |
| "The skill shows one pattern, so it's settled" | Skills carry trade-offs. Surface them; don't decide alone. |

Skills that need an addon you do not have installed: `limboai`, `beehave`, `popochiu`,
`dialogue-manager`, `phantom-camera`. Check `addons/` before loading one.

After implementing, `godot-code-review` validates against Godot-specific checklists.

## Tool mapping for OpenCode V2

Skills are written against Claude Code tool names. Substitute:

| Skill refers to | Use |
|---|---|
| `TodoWrite` | no todo tool exists; track the plan in a markdown file |
| `Task` with subagents | `subagent` (`agent: "general"`, plus `description` and `prompt`) |
| `Skill` | `skill` |
| `Read` / `Write` / `Edit` | `read` / `write` / `edit` |
| `apply_patch` | `patch` with `patchText` when available |
| `Bash` | `shell` (`command`, `workdir`, `timeout`, `background`) |
| `Glob` / `Grep` | `glob` / `grep` |