<#
.SYNOPSIS
    Fetches or refreshes the vendored Godot skill sources.

.DESCRIPTION
    Populates vendor/godot-skills/ with the skills from three upstream projects
    and points OpenCode at them via the `skills.paths` config field.

    Why not `opencode plugin add` / `plugin update`? All three upstream projects
    are broken as OpenCode plugins: godot-prompter exports a V1 plugin, which V2
    refuses to load, and @modastar/godot-skills has no entrypoint at all. Every
    `plugin` subcommand loads the package in order to inspect it, so all of them
    fail for these - and `plugin check` will not even warn, because it only
    considers entries that load. Vendoring sidesteps that entirely: update by
    re-running this script.

    Layout produced:

        vendor/godot-skills/
          _src/godot-prompter/       git clone; the pull target on re-runs
          _src/modastar/             npm tarball extract
          _src/gd-agentic/           git clone; curated on copy
          godot-prompter/skills/     copied, deduplicated
          modastar/skills/           copied, deduplicated
          gd-agentic/skills/         copied, deduplicated, allowlisted
          VERSIONS.txt               what is currently vendored

    The copy step is what applies collision policy, rather than relying on the
    order of `skills.paths` entries or on host source precedence:

      1. A skill authored in this project wins over anything vendored.
      2. Between the sources, godot-prompter wins, because its `godot-ui`
         covers Control, theming and anchors in depth while @modastar's is a
         one-paragraph summary.
      3. gd-agentic is listed last, so it also loses any future name collision.
         It is additionally allowlisted, because it ships 99 skills of which
         roughly 35 re-cover topics the other two already hold under different
         names. See $GD_AGENTIC_INCLUDE.

    Because deduplication happens on copy, the sources are never modified, so a
    later `git pull` of _src/godot-prompter cannot resurrect a removed skill.

    IMPORTANT: vendor/ is a derived artifact and is rebuilt from scratch on every
    run - Sync-Skills deletes each source's skills directory before re-copying it.
    Hand-edits to anything under vendor/ are therefore destroyed silently on the
    next run. To change what a skill says, either edit the upstream repo or add a
    post-copy patch step here; do not edit vendor/ in place. Project-owned
    guidance belongs in AGENTS.md, which is not regenerated.

.PARAMETER Force
    Delete and refetch all sources instead of updating them in place.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/setup-godot-skills.ps1
#>
[CmdletBinding()]
param(
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$VendorRoot = Join-Path $ProjectRoot 'vendor\godot-skills'
$SrcRoot = Join-Path $VendorRoot '_src'

function Write-Step($message) { Write-Host "==> $message" }
function Write-Detail($message) { Write-Host "    $message" }

function Assert-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) { return }
    foreach ($candidate in @('C:\Program Files\Git\cmd', 'C:\Program Files (x86)\Git\cmd')) {
        if (Test-Path $candidate) {
            $env:Path = "$candidate;$env:Path"
            Write-Step "Added git to PATH: $candidate"
            return
        }
    }
    throw 'git is not on PATH and no default install was found. Install Git for Windows, then re-run.'
}

function Invoke-Git {
    param([string[]] $GitArgs, [string] $WorkingDir)
    $output = & git -C $WorkingDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed in ${WorkingDir}:`n$output"
    }
    return $output
}

# --- curated allowlists --------------------------------------------------------
# Must be defined before $SOURCES, which reads it when it is constructed.
#
# GD-Agentic-Ships 99 skills, of which roughly 35 re-cover ground already held by
# godot-prompter / modastar under different names (godot-ability-system vs
# ability-system, godot-tweening vs godot-tween, godot-ui-theming vs godot-ui,
# godot-state-machine-advanced vs state-machine, ...). Vendoring those would give
# two skills per topic and make "load the matching skill" ambiguous.
#
# Deliberately NOT vendored, in case they are wanted later:
#   godot-game-loop-*    4 templates, overlap the genre skills
#   godot-adapt-*        5 porting guides, overlap responsive-ui/mobile-development
#   godot-platform-*     5 export targets, overlap mobile-development/xr-development
#   godot-theme-easter   novelty, not engineering guidance
$GD_AGENTIC_INCLUDE = @(
    # Orchestration hub. Carries its own 50 KB of architecture frameworks and
    # anti-pattern catalogs, so it earns its place even though its cross-links to
    # non-vendored siblings dangle. See AGENTS.md for how it fits the routing.
    'godot-master'
    # The repo's designated migration hub, and the sibling godot-master points at
    # hardest. Nothing in the other two sources covers version-to-version moves.
    'godot-version-migration'
    # Roles: analysis, review and implementation passes.
    'godot-analyst'
    'godot-auditor'
    'godot-builder'
    'godot-agent-vision'
    # Systems with no equivalent in the other two sources.
    'godot-combat-system'
    'godot-economy-system'
    'godot-quest-system'
    'godot-turn-system'
    'godot-rpg-stats'
    'godot-mechanic-revival'
    'godot-mechanic-secrets'
    'godot-monte-carlo-balancer'
    # Genre design. The single largest genuine gap: the other 69 skills are all
    # engine-mechanism oriented, none are genre oriented.
    'godot-genre-action-rpg'
    'godot-genre-battle-royale'
    'godot-genre-card-game'
    'godot-genre-educational'
    'godot-genre-fighting'
    'godot-genre-horror'
    'godot-genre-idle-clicker'
    'godot-genre-metroidvania'
    'godot-genre-moba'
    'godot-genre-open-world'
    'godot-genre-party'
    'godot-genre-platformer'
    'godot-genre-puzzle'
    'godot-genre-racing'
    'godot-genre-rhythm'
    'godot-genre-roguelike'
    'godot-genre-romance'
    'godot-genre-rts'
    'godot-genre-sandbox'
    'godot-genre-shooter'
    'godot-genre-shooter-fps'
    'godot-genre-simulation'
    'godot-genre-sports'
    'godot-genre-stealth'
    'godot-genre-survival'
    'godot-genre-tower-defense'
    'godot-genre-visual-novel'
)

# --- sources -------------------------------------------------------------------
# Ordered by precedence: earlier sources win a skill ID collision.
$SOURCES = @(
    [pscustomobject]@{
        Id          = 'godot-prompter'
        Kind        = 'git'
        Location    = 'https://github.com/jame581/GodotPrompter.git'
        DirName     = 'godot-prompter'
        # A git clone has the skills at the repository root.
        SkillsPath  = 'skills'
        Description = 'jame581/GodotPrompter'
        # $null means vendor every skill this source ships.
        Include     = $null
    },
    [pscustomobject]@{
        Id          = 'modastar'
        Kind        = 'npm'
        Location    = '@modastar/godot-skills'
        DirName     = 'modastar'
        # An npm tarball nests everything under `package/`.
        SkillsPath  = 'package\skills'
        Description = '@modastar/godot-skills (npm)'
        Include     = $null
    },
    [pscustomobject]@{
        Id          = 'gd-agentic'
        Kind        = 'git'
        Location    = 'https://github.com/thedivergentai/GD-Agentic-Skills.git'
        DirName     = 'gd-agentic'
        SkillsPath  = 'skills'
        Description = 'thedivergentai/GD-Agentic-Skills'
        # Curated, not wholesale. Listed last so it also loses any future
        # collision with the other two sources.
        Include     = $GD_AGENTIC_INCLUDE
    }
)

function Install-GitSource($Source, $Destination) {
    if (Test-Path $Destination) {
        if ($Force) {
            Write-Step "Removing existing clone $Destination"
            Remove-Item $Destination -Recurse -Force
        } else {
            Write-Step "Updating $($Source.Id) (git pull)"
            [void](Invoke-Git @('pull', '--ff-only', '--quiet') $Destination)
            $rev = (Invoke-Git @('rev-parse', '--short', 'HEAD') $Destination) -join ''
            return "git $rev"
        }
    }
    Write-Step "Cloning $($Source.Id)"
    [void](Invoke-Git @('clone', '--depth', '1', '--quiet', $Source.Location, $Destination) $ProjectRoot)
    $rev = (Invoke-Git @('rev-parse', '--short', 'HEAD') $Destination) -join ''
    return "git $rev"
}

function Install-NpmSource($Source, $Destination) {
    if (Test-Path $Destination) {
        if ($Force) {
            Write-Step "Removing existing extract $Destination"
            Remove-Item $Destination -Recurse -Force
        } else {
            Write-Step "Refetching $($Source.Id) (npm tarball)"
        }
    } else {
        Write-Step "Downloading $($Source.Id)"
    }

    # Resolve the published version so the tarball URL is explicit rather than
    # depending on a registry shorthand.
    $meta = Invoke-RestMethod "https://registry.npmjs.org/$($Source.Location)/latest"
    $tarball = $meta.dist.tarball

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $tgz = Join-Path $Destination 'package.tgz'
    try {
        Invoke-WebRequest $tarball -OutFile $tgz -UseBasicParsing
        # npm tarballs contain a single top-level `package/` directory.
        & tar -xzf $tgz -C $Destination
        if ($LASTEXITCODE -ne 0) { throw "tar failed to extract $tgz" }
    } finally {
        Remove-Item $tgz -Force -ErrorAction SilentlyContinue
    }
    return "npm $($meta.version)"
}

# --- local precedence ----------------------------------------------------------
function Get-LocalSkillIds {
    $ids = @{}
    foreach ($relative in @('.agents\skills', '.opencode\skills', '.claude\skills')) {
        $dir = Join-Path $ProjectRoot $relative
        if (-not (Test-Path $dir)) { continue }
        foreach ($entry in Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue) {
            if (Test-Path (Join-Path $entry.FullName 'SKILL.md')) { $ids[$entry.Name] = $relative }
        }
    }
    return $ids
}

# --- copy with collision policy ------------------------------------------------
function Sync-Skills {
    param(
        [string]    $SourceSkills,
        [string]    $DestSkills,
        [string]    $SourceId,
        [hashtable] $Claimed,
        [hashtable] $LocalIds,
        [string[]]  $Include
    )

    if (-not (Test-Path $SourceSkills)) { throw "No skills directory at $SourceSkills" }

    $available = @(Get-ChildItem $SourceSkills -Directory | Where-Object {
        -not $_.Name.StartsWith('.') -and (Test-Path (Join-Path $_.FullName 'SKILL.md'))
    } | ForEach-Object { $_.Name })

    # An allowlist rots silently when upstream renames a skill, so check it up
    # front and say so rather than quietly vendoring a subset.
    if ($Include) {
        $missing = @($Include | Where-Object { $available -notcontains $_ })
        if ($missing.Count -gt 0) {
            throw "Allowlisted skill(s) not present upstream at ${SourceSkills}: $($missing -join ', ')"
        }
        $wanted = @{}; $Include | ForEach-Object { $wanted[$_] = $true }
        Write-Detail ("curated: $($Include.Count) of $($available.Count) upstream skill(s) selected")
    }

    # Rebuild the destination so skills deleted upstream do not linger.
    if (Test-Path $DestSkills) { Remove-Item $DestSkills -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $DestSkills | Out-Null

    $copied = 0
    $skippedLocal = @()
    $skippedClaimed = @()

    foreach ($name in ($available | Sort-Object)) {
        if ($Include -and -not $wanted.ContainsKey($name)) { continue }

        if ($LocalIds.ContainsKey($name)) {
            $skippedLocal += $name
            continue
        }
        if ($Claimed.ContainsKey($name)) {
            $skippedClaimed += $name
            continue
        }

        $Claimed[$name] = $SourceId
        Copy-Item (Join-Path $SourceSkills $name) (Join-Path $DestSkills $name) -Recurse -Force
        $copied++
    }

    Write-Detail "$copied skill(s) copied"
    if ($skippedLocal.Count -gt 0) {
        Write-Detail ("skipped, shadowed by a project skill: " + ($skippedLocal -join ', '))
    }
    if ($skippedClaimed.Count -gt 0) {
        Write-Detail ("skipped, lost to a higher-precedence source: " + ($skippedClaimed -join ', '))
    }
    return $copied
}

# --- main ----------------------------------------------------------------------
Assert-Git

$localIds = Get-LocalSkillIds
Write-Step "Project skills taking precedence: $(if ($localIds.Count) { ($localIds.Keys | Sort-Object) -join ', ' } else { '(none)' })"

New-Item -ItemType Directory -Force -Path $VendorRoot | Out-Null

$versions = @()
$claimed = @{}
$total = 0

foreach ($source in $SOURCES) {
    $srcDir = Join-Path $SrcRoot $source.DirName
    if ($source.Kind -eq 'git') {
        $version = Install-GitSource $source $srcDir
    } else {
        $version = Install-NpmSource $source $srcDir
    }
    $versions += [pscustomobject]@{ Source = $source.Description; Version = $version }

    $sourceSkills = Join-Path $srcDir $source.SkillsPath
    $destSkills = Join-Path (Join-Path $VendorRoot $source.DirName) 'skills'
    $total += Sync-Skills $sourceSkills $destSkills $source.Id $claimed $localIds $source.Include
}

# CRITICAL: tell Godot's filesystem scanner to skip this whole tree.
#
# vendor/ lives INSIDE the Godot project, so without this marker Godot imports
# and compiles the skills' example .gd files as if they were project code. The
# gd-agentic skills ship 1,683 of them, and two collide with real game classes:
#
#   res://vendor/.../godot-genre-survival/scripts/interactable.gd   class_name Interactable
#   res://vendor/.../godot-genre-visual-novel/scripts/dialogue_ui.gd class_name DialogueUI
#
# A colliding class_name makes the game's own script fail to parse with
# 'Class "Interactable" hides a global script class', which cascades: the base
# class will not load, so player.gd sees interact() as returning void, and every
# interactable subclass fails too. That is seven broken scripts from an unrelated
# directory. An empty .gdignore fixes it; it must be recreated on every run
# because vendor/ is a build artifact and is wiped by Sync-Skills.
$gdignore = Join-Path $VendorRoot '.gdignore'
if (-not (Test-Path $gdignore)) {
    New-Item -ItemType File -Force -Path $gdignore | Out-Null
    Write-Step 'Wrote vendor/.gdignore (keeps Godot from compiling skill examples)'
}

$manifest = @('# Vendored Godot skills - generated by tools/setup-godot-skills.ps1', '## Do not edit; re-run the script to refresh.', '')
foreach ($entry in $versions) { $manifest += "- $($entry.Source): $($entry.Version)" }
$manifest += ''
$manifest += "Total skills: $total"
Set-Content -Path (Join-Path $VendorRoot 'VERSIONS.txt') -Value $manifest -Encoding UTF8

Write-Step "Vendored $total skill(s) into $VendorRoot"

# Best effort: pick the new skills up without restarting the app.
$cliRoot = Join-Path $env:APPDATA 'ai.opencode.desktop\cli'
if (Test-Path $cliRoot) {
    $cli = Get-ChildItem -Path $cliRoot -Recurse -Filter 'opencode-cli.exe' -ErrorAction SilentlyContinue |
        Sort-Object { try { [version](Split-Path $_.DirectoryName -Leaf) } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if ($cli) {
        Write-Step 'Reloading OpenCode...'
        & $cli reload | Out-Null
    }
}

Write-Host ''
Get-Content (Join-Path $VendorRoot 'VERSIONS.txt') | ForEach-Object { Write-Host "  $_" }