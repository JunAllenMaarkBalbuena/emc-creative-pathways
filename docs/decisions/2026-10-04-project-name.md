# Project name

Settled 2026-10-04.

| | |
|---|---|
| Short name (`config/name`, window title) | **EMC Creative Pathways** |
| Formal title (documentation, title screen later) | **EMC Creative Pathways: Promoting Engagement in the BSEMC-DAT Program through Gamified Simulations** |
| User data folder | `%APPDATA%\bsemc_dat_progress` (Windows), `~/Library/Application Support/bsemc_dat_progress` (macOS), `~/.local/share/bsemc_dat_progress` (Linux) |

## Why the short name is in `config/name`

`application/config/name` becomes the window titlebar text and the label in the
editor's project list. The formal title is 104 characters; in a titlebar it is
truncated into something meaningless. So `config/name` carries the short name and
the formal title is recorded here.

`TitleLabel` in `scenes/main_menu.tscn` was widened from 560 px to 800 px to match.
It is a 72 px cursive label: "EMC Simulator" (13 chars) fitted the old 560 px, but
"EMC Creative Pathways" (20 chars) needs roughly 720 px and would have clipped
against the 1280 px viewport.

## The important part: `user://` is now pinned

```ini
config/use_custom_user_dir=true
config/custom_user_dir_name="bsemc_dat_progress"
```

Without these, the user data folder is derived from `config/name`, so **every future
rename silently resets player data**. With them, the data folder is independent of the
display name and no rename can touch it again.

Note this moves `user://` out of `Godot/app_userdata/` and into the platform's normal
application data location, per Godot's documented behaviour. Data migrated from
`%APPDATA%\Godot\app_userdata\Progress_3_BS_EMC_SEM\`:

| Item | State |
|---|---|
| `settings.json` (126 b) | copied, confirmed being written back after the switch |
| `level_progression.json` (71 b) | copied |
| `drawings/`, `exports/`, `models/` | recreated (were empty) |

The old folder was **copied, not moved**, and is left in place as rollback. It is
1.4 MB, almost entirely `shader_cache/` and `logs/`, which regenerate. `drawings/`,
`exports/` and `models/` were empty, so no student work was at risk.

## Not done: the formal title is not on the title screen

The only free text slot on the menu is `VersionLabel` — a bottom-left label 201 px
wide, currently reading "v0.1.0 — Capstone Project". The formal title is 104
characters and needs roughly 620 px at that label's font size. Putting it there
would clip it and would also cost the version display, since one label cannot hold
both.

Adding it properly means either a new centred `Label` node with its own
`LabelSettings` sub-resource, or reworking `VersionLabel`'s role and anchoring. Both
are real layout changes to a hand-maintained `.tscn`, so they are deferred rather
than done blind. The formal title lives here in the meantime.

## Still pending

The GitHub repository is still `progress_2_EMC_simulator`. Renaming it to
`emc-creative-pathways` needs the web UI (GitHub CLI is not installed here). GitHub
redirects the old URL, so existing links keep working. `origin` and the handoff docs
need updating once that is done.