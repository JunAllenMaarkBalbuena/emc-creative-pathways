<#
.SYNOPSIS
    Verifies that this Godot project tree is sound, and safe to hand to someone else.

.DESCRIPTION
    Three gates, in order:

      1. Import - runs --headless --import so .godot/ and the class cache exist.
      2. Boot   - boots and asserts a clean exit with no engine errors.
      3. Tests  - runs every tests\*.gd that extends SceneTree, reports PASS/FAIL.

    Step 1 is not optional and --quit is not a substitute for --import. On a fresh
    clone .godot/ does not exist, so .godot/global_script_class_cache.cfg does not
    exist either, and every class_name fails to resolve. The suite then reports a
    wall of invented failures - "Could not find type LevelDefinition", "Identifier
    PrimitiveSpawner not declared", "Failed to instantiate an autoload" - none of
    which indicate broken code. Only --import builds the cache. If step 1 cannot
    build it, this script stops rather than reporting those as test failures.

    Exit code is NOT a test signal. The suite communicates through printed
    PASS:/FAIL: markers and several tests exit 0 while printing errors, so this
    script parses the output rather than trusting $LASTEXITCODE.

.PARAMETER Godot
    Path to Godot_v4.7.2-stable_win64_console.exe. Autodetected if omitted. Use the
    _console variant: the non-console build does not emit headless output.

.PARAMETER SkipTests
    Only run the warm-up and boot gates.

.PARAMETER Only
    Run only the named test scripts, e.g. -Only test_modeling_grid.gd

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\verify-project.ps1

.NOTES
    Baseline on 2026-10-04: boot exits 0 with zero errors; 19-20 of 20 SceneTree
    tests clean. test_full_lab_sweep.gd is flaky and is reported as WARN, not FAIL.

    The first run on a fresh clone imports every asset and takes minutes. Later
    runs are fast. The editor does this same import the first time it opens a
    project, so a collaborator who opens Godot first will not notice it.
#>
[CmdletBinding()]
param(
    [string]   $Godot,
    [switch]   $SkipTests,
    [string[]] $Only
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot

# Exit 0 does not mean "tests passed" - see .DESCRIPTION.
$KnownFlaky = @('test_full_lab_sweep.gd')

function Find-Godot {
    param([string] $Explicit)

    if ($Explicit) {
        if (Test-Path $Explicit) { return $Explicit }
        throw "Godot not found at '$Explicit'."
    }

    $onPath = Get-Command godot* -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '_console\.exe$' } |
              Select-Object -First 1
    if ($onPath) { return $onPath.Source }

    $onPath = Get-Command godot* -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { return $onPath.Source }

    # The engine is frequently installed in a folder that is not on PATH.
    $roots = @(
        "$env:USERPROFILE\Downloads",
        "$env:LOCALAPPDATA\Programs",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        'C:\Godot', 'C:\tools'
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($r in $roots) {
        $hit = Get-ChildItem $r -Recurse -Depth 3 -Filter 'Godot*_console.exe' -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    throw @"
Godot console binary not found. Pass it explicitly:

    .\tools\verify-project.ps1 -Godot 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'

Use the _console build - the plain build does not print headless output.
"@
}

function Invoke-Godot {
    param([string[]] $GodotArgs)

    $all = @($GodotArgs)
    $out = & $script:GodotBin --headless --path $Root @all 2>&1 |
           ForEach-Object { [string]$_ }
    return [pscustomobject]@{
        Exit  = $LASTEXITCODE
        Lines = $out
    }
}

function Test-EngineErrors {
    param([string[]] $Lines)
    # "Failed to load script" on a cold cache is the known phantom; the warm-up
    # gate exists so that by the time we get here it should not appear.
    return @($Lines | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' })
}

# ---------------------------------------------------------------- locate engine
$GodotBin = Find-Godot -Explicit $Godot
Write-Host "engine : $GodotBin" -ForegroundColor DarkGray

$ver = @(& $GodotBin --version 2>&1 | ForEach-Object { [string]$_ }) | Select-Object -First 1
Write-Host "version: $ver" -ForegroundColor DarkGray
if ($ver -notmatch '^4\.7\.2\.') {
    Write-Warning "This project pins 4.7.2.stable. Got '$ver'. Results may not be comparable."
}

$failed = $false
$bootGateRan = $false

# ------------------------------------------------------------------ 1. warm up
Write-Host "`n[1/3] importing (builds .godot/ and the class cache)" -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
# --import, not --quit. --quit boots without scanning for scripts, so it never
# creates .godot/global_script_class_cache.cfg. On a fresh clone that file does
# not exist, every class_name then fails to resolve, and the whole suite fails
# with phantom errors ("Could not find type LevelDefinition", "Identifier
# PrimitiveSpawner not declared"). Those look like broken code but are only a
# missing cache. --import is what actually builds it.
$warm = Invoke-Godot @('--import')
$cache = Join-Path $Root '.godot\global_script_class_cache.cfg'

if (Test-Path $cache) {
    Write-Host ("      cache built ({0:N1} KB) in {1:N0}s" -f ((Get-Item $cache).Length / 1KB), $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
} else {
    # Hard fail. Every later gate depends on this file, and continuing produces
    # a wall of invented errors that hides whatever is genuinely wrong.
    Write-Host "      no class cache at .godot\global_script_class_cache.cfg" -ForegroundColor Red
    if ($warm.Lines) {
        Write-Host '      import said:' -ForegroundColor Red
        $warm.Lines | Select-Object -Last 15 | ForEach-Object { Write-Host "        $_" -ForegroundColor Red }
    }
    Write-Host ''
    Write-Host 'VERIFY FAILED - the class cache could not be built, so no later' -ForegroundColor Red
    Write-Host 'result would be meaningful. Check the import output above.' -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------------- 2. boot
Write-Host "`n[2/3] headless boot" -ForegroundColor Cyan
$boot = Invoke-Godot @('--quit')
# Wrapped in @() deliberately: PowerShell unrolls an empty array returned from a
# function down to $null, and $null.Count throws under Set-StrictMode. That throw
# used to abort this gate and the script still printed VERIFY OK - a false pass.
$bootErrors = @(Test-EngineErrors $boot.Lines)
Write-Host ("      exit {0}, {1} engine error(s)" -f $boot.Exit, $bootErrors.Count)
if ($bootErrors.Count -gt 0) {
    $failed = $true
    $bootErrors | Select-Object -First 15 | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
} elseif ($boot.Exit -ne 0) {
    $failed = $true
    Write-Host "      non-zero exit with no engine error" -ForegroundColor Red
} else {
    Write-Host "      clean" -ForegroundColor Green
}
$bootGateRan = $true

# -------------------------------------------------------------------- 3. tests
if ($SkipTests) {
    Write-Host "`n[3/3] tests skipped (-SkipTests)" -ForegroundColor DarkGray
} else {
    Write-Host "`n[3/3] test suite" -ForegroundColor Cyan

    $tests = @()
    if ($Only) {
        $tests = $Only
    } else {
        Get-ChildItem (Join-Path $Root 'tests') -Filter '*.gd' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $head = (Get-Content $_.FullName -TotalCount 3) -join ' '
                if ($head -match 'extends\s+SceneTree') { $tests += $_.Name }
            }
    }

    if ($tests.Count -eq 0) {
        Write-Warning 'no runnable tests found'
    }

    $ok = 0; $warn = 0; $bad = 0
    foreach ($t in $tests) {
        $r = Invoke-Godot @('--script', "res://tests/$t")
        $fails = @($r.Lines | Where-Object { $_ -match '\bFAIL|\bFAILED|assertion failed' })
        $errs  = @(Test-EngineErrors $r.Lines)

        if ($fails.Count -eq 0 -and $errs.Count -eq 0) {
            $ok++
            Write-Host ("      PASS  {0}" -f $t) -ForegroundColor DarkGray
        } elseif ($KnownFlaky -contains $t) {
            $warn++
            Write-Host ("      WARN  {0}  (known flaky)" -f $t) -ForegroundColor Yellow
        } else {
            $bad++
            $failed = $true
            Write-Host ("      FAIL  {0}" -f $t) -ForegroundColor Red
            @($fails + $errs) | Select-Object -First 3 | ForEach-Object { Write-Host "            $_" -ForegroundColor Red }
        }
    }

    Write-Host ("`n      {0} pass, {1} warn, {2} fail  (of {3})" -f $ok, $warn, $bad, $tests.Count) -ForegroundColor Cyan
}

# ---------------------------------------------------------------------- verdict
Write-Host ''
if (-not $bootGateRan) {
    # A gate that aborted must never be reported as a pass.
    Write-Host 'VERIFY FAILED - the boot gate did not complete' -ForegroundColor Red
    exit 1
}
if ($failed) {
    Write-Host 'VERIFY FAILED - do not hand this tree off' -ForegroundColor Red
    exit 1
}
Write-Host 'VERIFY OK - safe to hand off' -ForegroundColor Green
exit 0