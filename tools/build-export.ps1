<#
.SYNOPSIS
    Exports the project using the presets in export_presets.cfg.

.DESCRIPTION
    Wraps the two Godot CLI export calls so a build is one command and its result
    is actually checked rather than assumed.

    Two traps this exists to avoid:

      1. Godot reports export failures on stderr, and PowerShell's default error
         handling does not treat stderr output as failure. A naive wrapper prints
         a success-looking message after a failed export. Here stderr is captured
         to a file and scanned for errors, and a non-zero exit is not trusted on
         its own because Godot can exit 0 while having complained.

      2. Exporting writes into the project directory. Output goes to build/,
         which is gitignored, so building never dirties the tree it builds from.

.PARAMETER Preset
    Which preset to build. Defaults to building all of them.

.PARAMETER Debug
    Build the debug template instead of the release template.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build-export.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build-export.ps1 -Preset Web
#>
[CmdletBinding()]
param(
    [string[]] $Preset,
    [switch] $Debug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

try {
    # ------------------------------------------------------------------- engine
    $engine = $null
    $candidates = @(
        'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe',
        'C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $engine = $c; break } }
    if (-not $engine) {
        $onPath = Get-Command godot* -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($onPath) { $engine = if ($onPath -is [string]) { $onPath } else { $onPath.Source } }
    }
    if (-not $engine) {
        throw 'Godot 4.7.2 console binary not found. Pass its path or put it on PATH.'
    }
    Write-Host "engine  : $engine" -ForegroundColor DarkGray

    $ver = (& $engine --headless --version 2>&1 | ForEach-Object { [string]$_ }).Trim()
    Write-Host "version : $ver" -ForegroundColor DarkGray

    # ------------------------------------------------------------------ presets
    $presetFile = Join-Path $Root 'export_presets.cfg'
    if (-not (Test-Path $presetFile)) { throw "no export_presets.cfg at $presetFile" }

    $declared = @(Select-String -Path $presetFile -Pattern '^name="(.+)"$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value })
    Write-Host "presets : $($declared -join ', ')" -ForegroundColor DarkGray

    if (-not $Preset -or $Preset.Count -eq 0) { $Preset = $declared }
    foreach ($p in $Preset) {
        if ($declared -notcontains $p) {
            throw "preset '$p' is not in export_presets.cfg. Available: $($declared -join ', ')"
        }
    }

    # ----------------------------------------------------------------- templates
    # One version directory, named for the exact engine build. A mismatched
    # directory is the usual cause of "no export template found" on a machine
    # that genuinely has templates installed.
    $build = ($ver -split '\.')[0..3] -join '.'   # 4.7.2.stable
    $tplDir = Join-Path $env:APPDATA "Godot\export_templates\$build"
    if (-not (Test-Path $tplDir)) {
        Write-Host "no export templates for $build at:" -ForegroundColor Red
        Write-Host "  $tplDir" -ForegroundColor Red
        Write-Host 'Install them from Editor > Manage Export Templates, matching this' -ForegroundColor Yellow
        Write-Host 'exact engine version. A different patch version will not work.' -ForegroundColor Yellow
        throw 'export templates missing'
    }
    $tplCount = @(Get-ChildItem $tplDir -File -EA SilentlyContinue).Count
    Write-Host "templates: $tplCount files in $tplDir" -ForegroundColor DarkGray

    # -------------------------------------------------------------------- build
    $mode = if ($Debug) { 'debug' } else { 'release' }
    $flag = if ($Debug) { '--export-debug' } else { '--export-release' }
    $results = @()

    foreach ($p in $Preset) {
        # Pull the export_path for this preset straight out of the file rather
        # than duplicating it here, so the two can never disagree.
        $pathLine = $null
        $inPreset = $false
        foreach ($line in Get-Content $presetFile) {
            if ($line -match '^\[preset\.\d+\]$') { $inPreset = $false; continue }
            if ($line -match '^name="(.+)"$') { $inPreset = ($Matches[1] -eq $p) }
            if ($inPreset -and $line -match '^export_path="(.+)"$') { $pathLine = $Matches[1]; break }
        }
        if (-not $pathLine) { throw "could not read export_path for preset '$p'" }

        $outPath = Join-Path $Root $pathLine
        $outDir = Split-Path -Parent $outPath
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

        Write-Host ''
        Write-Host "building '$p' ($mode) -> $pathLine" -ForegroundColor Cyan

        # stderr to a file: this is the whole point. See the note in .DESCRIPTION.
        $errFile = Join-Path $env:TEMP ("export_{0}_stderr.txt" -f ($p -replace '\W', '_'))
        $outFile = Join-Path $env:TEMP ("export_{0}_stdout.txt" -f ($p -replace '\W', '_'))
        $proc = Start-Process -FilePath $engine `
            -ArgumentList @('--headless', $flag, "`"$p`"", "`"$outPath`"") `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $code = $proc.ExitCode

        $stderr = if (Test-Path $errFile) { @(Get-Content $errFile -EA SilentlyContinue) } else { @() }
        $looksBad = @($stderr | Where-Object { $_ -match '(?i)\berror\b|failed|cannot|not found|no export template' })

        Write-Host "  exit code : $code"
        if ($stderr.Count -gt 0) {
            Write-Host "  stderr    : $($stderr.Count) line(s)" -ForegroundColor DarkGray
            $stderr | Select-Object -First 12 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
        if ($looksBad.Count -gt 0) {
            Write-Host "  $($looksBad.Count) line(s) look like errors:" -ForegroundColor Red
            $looksBad | Select-Object -First 12 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }

        # Trust the artifact, not the exit code. Godot has been seen to exit 0
        # having failed to write anything.
        $produced = Test-Path $outPath
        if ($produced) {
            $sz = (Get-Item $outPath).Length
            Write-Host ("  produced  : {0} ({1:N2} MB)" -f (Split-Path $outPath -Leaf), ($sz / 1MB)) -ForegroundColor Green
        } else {
            Write-Host "  produced  : NOTHING at $outPath" -ForegroundColor Red
        }

        $results += [pscustomobject]@{
            Preset   = $p
            Exit     = $code
            Produced = $produced
            Bytes    = if ($produced) { (Get-Item $outPath).Length } else { 0 }
            Path     = $pathLine
            Errors   = $looksBad.Count
        }
    }

    # ------------------------------------------------------------------ summary
    Write-Host ''
    Write-Host 'summary' -ForegroundColor Cyan
    $results | ForEach-Object {
        $ok = $_.Produced -and $_.Exit -eq 0 -and $_.Errors -eq 0
        $mark = if ($ok) { 'OK  ' } else { 'FAIL' }
        $colour = if ($ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0}  {1,-18} {2,10:N2} MB  exit={3} errorlines={4}" -f `
            $mark, $_.Preset, ($_.Bytes / 1MB), $_.Exit, $_.Errors) -ForegroundColor $colour
    }

    $failed = @($results | Where-Object { -not $_.Produced -or $_.Exit -ne 0 -or $_.Errors -gt 0 })
    Write-Host ''
    if ($failed.Count -gt 0) {
        Write-Host "$($failed.Count) of $($results.Count) preset(s) did not build cleanly." -ForegroundColor Red
        exit 1
    }
    Write-Host 'All requested presets built cleanly.' -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}