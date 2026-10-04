<#
.SYNOPSIS
    Builds a handoff zip of the project from the committed tree.

.DESCRIPTION
    Produces a zip by asking git for HEAD, not by zipping the folder. That
    distinction is the whole point:

      - .godot/ (526 MB of machine-specific import cache) is excluded, because it
        is gitignored. Zipping the folder would ship it.
      - The archive provably equals the last commit. A folder zip cannot.
      - Uncommitted work cannot leak in by accident.

    The recipient gets a tree that is byte-identical to the commit you pushed.

    After unzipping they should run:

        powershell -ExecutionPolicy Bypass -File tools\verify-project.ps1

    That regenerates .godot/ and proves the tree is sound.

.PARAMETER OutputDir
    Where to write the zip. Defaults to the repository's dist/ directory, which is
    gitignored, so packaging never dirties the tree it is packaging.

.PARAMETER Ref
    Git ref to archive. Defaults to HEAD.

.PARAMETER Name
    Archive base name. Defaults to the repo directory name plus the short ref.

.PARAMETER AllowDirty
    Archive even with uncommitted changes in the working tree. Off by default:
    the archive will not match what you are looking at if you allow it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\package-handoff.ps1
#>
[CmdletBinding()]
param(
    [string] $OutputDir,
    [string] $Ref = 'HEAD',
    [string] $Name,
    [switch] $AllowDirty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

try {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        foreach ($c in @('C:\Program Files\Git\cmd\git.exe', "${env:ProgramFiles(x86)}\Git\cmd\git.exe")) {
            if (Test-Path $c) { $git = $c; break }
        }
    }
    if (-not $git) { throw 'git not found and not on PATH.' }
    if ($git -is [string]) { $gitExe = $git } else { $gitExe = $git.Source }

    # ------------------------------------------------------------- dirty check
    $dirty = @(& $gitExe status --porcelain 2>&1 | ForEach-Object { [string]$_ })
    if ($dirty.Count -gt 0 -and -not $AllowDirty) {
        Write-Host "working tree has $($dirty.Count) uncommitted change(s):" -ForegroundColor Yellow
        $dirty | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
        if ($dirty.Count -gt 20) { Write-Host "  ... and $($dirty.Count - 20) more" -ForegroundColor DarkYellow }
        throw @'
Refusing to package a dirty tree: the zip would not match the commit.
Commit or stash first, or pass -AllowDirty if you know the difference is safe.
'@
    }
    if ($dirty.Count -gt 0) {
        Write-Warning "packaging despite $($dirty.Count) uncommitted change(s) (-AllowDirty)"
    }

    # ----------------------------------------------------------------- metadata
    $short  = (& $gitExe rev-parse --short $Ref 2>&1 | ForEach-Object { [string]$_ }).Trim()
    $subj   = (& $gitExe log -1 --format=%s $Ref 2>&1 | ForEach-Object { [string]$_ }).Trim()
    $branch = (& $gitExe rev-parse --abbrev-ref HEAD 2>&1 | ForEach-Object { [string]$_ }).Trim()

    if (-not $OutputDir) { $OutputDir = Join-Path $Root 'dist' }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null }
    if (-not $Name) {
        $repo = Split-Path -Leaf $Root
        $Name = "$repo-$short"
    }
    $prefix = "$Name/"
    $zip = Join-Path $OutputDir "$Name.zip"

    if (Test-Path $zip) { Remove-Item $zip -Force }

    Write-Host "ref     : $Ref ($short)" -ForegroundColor DarkGray
    Write-Host "branch  : $branch" -ForegroundColor DarkGray
    Write-Host "subject : $subj" -ForegroundColor DarkGray

    # ----------------------------------------------------------------- archive
    & $gitExe archive --format=zip --prefix=$prefix --output=$zip $Ref 2>&1 |
        ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "git archive failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path $zip)) { throw "git archive reported success but produced no file" }

    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 2)
    $count = @(& $gitExe ls-tree -r --name-only $Ref 2>&1).Count

    Write-Host ''
    Write-Host "wrote $zip" -ForegroundColor Green
    Write-Host "  $mb MB, $count files, prefix '$prefix'" -ForegroundColor DarkGray

    # ------------------------------------------------------------ sanity checks
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $zipObj = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries = @($zipObj.Entries | ForEach-Object { $_.FullName })
        $bad = @($entries | Where-Object { $_ -match '(^|/)\.godot/' })
        if ($bad.Count -gt 0) {
            Write-Warning "archive contains $($bad.Count) .godot/ entries - it should contain none"
        } else {
            Write-Host '  confirmed: no .godot/ cache in the archive' -ForegroundColor DarkGray
        }
        if (-not @($entries | Where-Object { $_ -eq "$prefix/project.godot" })) {
            throw 'archive has no project.godot at its root - the prefix is wrong'
        }
    } finally {
        $zipObj.Dispose()
    }

    Write-Host ''
    Write-Host 'Recipient instructions:' -ForegroundColor Cyan
    Write-Host "  1. unzip $Name.zip" -ForegroundColor DarkGray
    Write-Host '  2. install Godot 4.7.2-stable (the _console build is handy for CLI use)' -ForegroundColor DarkGray
    Write-Host '  3. powershell -ExecutionPolicy Bypass -File tools\verify-project.ps1' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Step 3 imports every asset, which takes about 5 minutes on a first run' -ForegroundColor DarkGray
    Write-Host 'and builds the class cache. That import is not optional: without it every' -ForegroundColor DarkGray
    Write-Host 'class_name fails to resolve and the suite reports failures that are not real.' -ForegroundColor DarkGray
    Write-Host 'Opening the project in the editor does the same import automatically.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'The Godot skills are not in the archive (vendor/ is a build artifact).' -ForegroundColor DarkGray
    Write-Host 'To restore them: powershell -ExecutionPolicy Bypass -File tools\setup-godot-skills.ps1' -ForegroundColor DarkGray
}
finally {
    Pop-Location
}