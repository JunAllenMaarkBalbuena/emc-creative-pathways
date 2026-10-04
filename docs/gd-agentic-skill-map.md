# gd-agentic skill map

Reference for `vendor/godot-skills/gd-agentic/`. Loaded on demand - not injected into every
request. `AGENTS.md` carries the seven most-cited rows; this file has all of them.

## Why this exists

`thedivergentai/GD-Agentic-Skills` ships 99 skills and each one cross-references its siblings.
We vendor 41 of them (see `$GD_AGENTIC_INCLUDE` in `tools/setup-godot-skills.ps1`), so **31 skill
IDs cited by the vendored set are not installed**. They appear in two places:

| Where | Form | What happens |
|---|---|---|
| "Related Skills" section | Absolute GitHub URLs | Does not fail. Sends you to the web for content you usually have locally. |
| "Skill Chain" table | Bare skill IDs | **Fails to load.** Use the substitute below. |

All 31 are cited by gd-agentic skills only. Nothing else in the set is affected.

## Substitutions

`Refs` is how many times the absent ID appears across the 41 vendored SKILL.md files - a rough
guide to how likely you are to hit it.

| Referenced but absent | Refs | Load this instead |
|---|---|---|
| `godot-save-load-systems` | 8 | `save-load` |
| `godot-state-machine-advanced` | 8 | `state-machine` |
| `godot-camera-systems` | 7 | `camera-system` |
| `godot-navigation-pathfinding` | 7 | `godot-navigation` for pathfinding, `ai-navigation` for agent behaviour |
| `godot-input-handling` | 6 | `input-handling` |
| `godot-inventory-system` | 5 | `inventory-system` |
| `godot-ui-containers` | 5 | `godot-ui` |
| `godot-ability-system` | 4 | `ability-system` |
| `godot-audio-systems` | 4 | `audio-system` |
| `godot-tilemap-mastery` | 4 | `godot-tilemap-2d` |
| `godot-tweening` | 4 | `tween-animation` for the pattern, `godot-tween` for the terse API summary |
| `godot-characterbody-2d` | 3 | `godot-character-body` |
| `godot-resource-data-patterns` | 3 | `resource-pattern` |
| `godot-scene-management` | 3 | `scene-organization` |
| `godot-shaders-basics` | 3 | `shader-basics`, or `godot-gdshader` for a terse lookup |
| `godot-ai-navigation` | 2 | `ai-navigation` |
| `godot-autoload-architecture` | 2 | `dependency-injection` |
| `godot-multiplayer-networking` | 2 | `multiplayer-basics` |
| `godot-particles` | 2 | `particles-vfx` |
| `godot-physics-3d` | 2 | `physics-system` for the rules, `3d-essentials` for the 3D-side setup |
| `godot-procedural-generation` | 2 | `procedural-generation` |
| `godot-project-foundations` | 2 | `godot-project-setup` |
| `godot-raycasting-queries` | 2 | `physics-system` |
| `godot-2d-animation` | 1 | `animation-system` |
| `godot-3d-lighting` | 1 | `3d-essentials` |
| `godot-3d-world-building` | 1 | `3d-essentials` |
| `godot-animation-tree-mastery` | 1 | `animation-system` |
| `godot-dialogue-system` | 1 | `dialogue-system` |
| `godot-gdscript-mastery` | 1 | `gdscript-patterns` and `gdscript-advanced` |
| `godot-ui-rich-text` | 1 | `godot-ui` |
| `godot-ui-theming` | 1 | `godot-ui` |

Every substitute in the right-hand column was verified to exist in the installed 110.

## Not actually missing

`godot-debugging` is cited twice by **godot-prompter**, not by gd-agentic, and it resolves
normally - to this project's own `.agents/skills/godot-debugging`, which lives outside
`vendor/`. Nothing to substitute.

## Deliberately excluded

Not vendored, so citing them is equally broken. Listed here so their absence is a decision
rather than a mystery:

| Excluded | Reason | Use instead |
|---|---|---|
| `godot-game-loop-*` (4) | Overlaps the genre skills | `godot-genre-*` |
| `godot-adapt-*` (5) | Overlaps responsive-ui / mobile-development | `responsive-ui`, `mobile-development` |
| `godot-platform-*` (5) | Overlaps mobile-development / xr-development | `mobile-development`, `xr-development`, `export-pipeline` |
| `godot-theme-easter` | Novelty, not engineering guidance | - |

To vendor any of them, add the name to `$GD_AGENTIC_INCLUDE` and re-run the setup script. It
validates the allowlist against the upstream tree and fails loudly on a renamed skill, so a
stale entry cannot silently vendor a subset.

## Regenerating

The counts above come from scanning the 41 vendored SKILL.md files for backtick-quoted
`godot-*` identifiers that are not installed. Re-derive after a refresh with:

```powershell
$v = "vendor/godot-skills"
$avail = @{}; Get-ChildItem "$v/*/skills" -Directory | ForEach-Object { $avail[$_.Name] = 1 }
$hits = @{}
Get-ChildItem "$v/gd-agentic/skills/*/SKILL.md" | ForEach-Object {
  $self = Split-Path (Split-Path $_.FullName -Parent) -Leaf
  ([regex]::Matches((Get-Content $_.FullName -Raw), '`(godot-[a-z0-9-]+)`') | ForEach-Object {
     $_.Groups[1].Value } | Where-Object { $_ -ne $self -and -not $avail.ContainsKey($_) }
  ) | ForEach-Object { $hits[$_] = 1 + [int]$hits[$_] }
}
$hits.GetEnumerator() | Sort-Object Value -Descending | Format-Table Name, Value
```
