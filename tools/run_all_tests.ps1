<#
Runs every tools/_test_*.gd (and, with -IncludeChecks, the _check_*.gd in the project root) one
after another with the flags each needs, and prints a pass/fail table.

  powershell -ExecutionPolicy Bypass -File tools\run_all_tests.ps1 [-Filter haunt] [-IncludeChecks]
      [-Windowed] [-OutDir <dir>] [-Godot <godot_console.exe>] [-TimeoutSec 300]

A run FAILS when it crashes or exits non-zero, prints "SCRIPT ERROR" / "Parse Error", prints a line
starting with "FAIL" or "TIMEOUT", reports "FAILS n" / "fails n" with n > 0, misses its expected line, or runs
past its timeout (a test that hangs on an await). It is WARN when it passed but the engine printed
ERROR lines (known headless dummy-renderer noise is not counted, see $Noise). Exit code 3 from
_test_frenzy means "the wanted passenger is not aboard tonight": SKIP.
Logs and pictures go to <OutDir>\<test>.log and <OutDir>\<test>\; a summary.md is written there.
Most tests are observational (they print what happened rather than assert): read their logs too.
#>
param(
    [string]$Filter = "",
    [switch]$IncludeChecks,
    [switch]$Windowed,                   # run everything windowed (headless drops mesh/skin data)
    [string]$OutDir = "",
    [string]$Godot = "",
    [int]$TimeoutSec = 300
)

$ErrorActionPreference = "Stop"
$Project = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $Godot = if ($env:GODOT) { $env:GODOT } else { "A:\Tools\Godot_v4.7.2-stable_win64.exe\godot_console.exe" }
}
if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot (pass -Godot or set GODOT)" }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ("trainwreck_tests\" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
New-Item -ItemType Directory -Force $OutDir | Out-Null

# Headless dummy-renderer noise (memory: headless-test-gotchas): not a game bug.
$Noise = 'already initialized RID|wrong RID|surface_get_arrays|merge_group|ObjectDB instances leaked|resources still in use at exit|rendering.dummy|RendererDummy|rid_owner.h|unimplemented base type encountered'

# How each test is run. Args: "{out}" becomes that run's picture folder.
#   Win: needs a window (pictures, meshes, skins).  Fps: --fixed-fps.  Expect: regex that must appear.
#   Skip: exit code that means "nothing to test tonight".
$Known = @{
    "_test_bunk"       = @(@{ Args = @("{out}"); Win = $true })
    "_test_economy"    = @(@{ Args = @("-"); Timeout = 600; Expect = 'FAILS 0' })
    "_test_edges"      = @(@{ })
    "_test_errands"    = @(@{ })
    "_test_escort"     = @(@{ Name = "_test_escort anomaly"; Args = @("anomaly") },
                           @{ Name = "_test_escort normal"; Args = @("normal") })
    "_test_frenzy"     = @(@{ Name = "_test_frenzy exposed"; Args = @("-", "exposed"); Skip = 3 },
                           @{ Name = "_test_frenzy arrest"; Args = @("-", "arrest"); Skip = 3 },
                           @{ Name = "_test_frenzy hunt"; Args = @("-", "hunt"); Skip = 3 },
                           @{ Name = "_test_frenzy abort"; Args = @("-", "abort"); Skip = 3 })
    "_test_frontend"   = @(@{ Args = @("{out}"); Win = $true })
    "_test_haunt"      = @(@{ Name = "_test_haunt calm coffee"; Args = @("calm", "coffee"); Expect = 'RESULT' },
                           @{ Name = "_test_haunt break ebrake"; Args = @("break", "ebrake"); Expect = 'FIXED incident' })
    "_test_haunt_mike" = @(@{ Expect = 'RESULT' })
    "_test_horror"     = @(@{ })
    "_test_mike"       = @(@{ Expect = 'MIKE LOG'; Timeout = 600 })
    "_test_pacing"     = @(@{ Args = @("37", "4"); Fps = 30; Timeout = 900; Expect = 'PACING OK' })
    "_test_passing"    = @(@{ Args = @("{out}"); Win = $true; Expect = 'RESULT events [1-9]' })
    "_test_station_life" = @(@{ Win = $true; Expect = 'RESULT ok' })
    # root checks (-IncludeChecks)
    "_check_passengers" = @(@{ Fps = 30; Timeout = 600 })
    "_check_townfolk"   = @(@{ Win = $true; Timeout = 900 })
    "_check_boarding"   = @(@{ })
    "_check_journey"    = @(@{ })
    "_check_train"      = @(@{ })
    "_check_mech"       = @(@{ Win = $true })      # (takes pictures: stalls headless)
    "_check_audio"      = @(@{ })
}

# A log another handle may still hold open: read it shared, retrying a few times.
function Read-Shared([string]$path) {
    for ($k = 0; $k -lt 10; $k++) {
        if (-not (Test-Path $path)) { return "" }
        try {
            $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { return (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    return "(could not read $path)"
}

$scripts = @(Get-ChildItem (Join-Path $Project "tools") -Filter "_test_*.gd" | Sort-Object Name)
if ($IncludeChecks) { $scripts += @(Get-ChildItem $Project -Filter "_check_*.gd" | Sort-Object Name) }

$runs = @()
foreach ($s in $scripts) {
    $base = [IO.Path]::GetFileNameWithoutExtension($s.Name)
    $rel = $s.FullName.Substring($Project.Length + 1).Replace("\", "/")
    $variants = if ($Known.ContainsKey($base)) { $Known[$base] } else { @(@{ }) }   # new tests: headless, no args
    foreach ($v in $variants) {
        $name = if ($v.Name) { $v.Name } else { $base }
        if ($Filter -and $name -notmatch $Filter) { continue }
        $runs += [pscustomobject]@{
            Name = $name; Script = $rel; Args = @($v.Args | Where-Object { $_ -ne $null })
            Win = [bool]($v.Win -or $Windowed); Fps = $v.Fps; Expect = $v.Expect; Skip = $v.Skip
            Timeout = if ($v.Timeout) { $v.Timeout } else { $TimeoutSec }
        }
    }
}
if ($runs.Count -eq 0) { Write-Host "No tests match '$Filter'."; exit 1 }

Write-Host ("Running {0} tests -> {1}" -f $runs.Count, $OutDir)
$results = @()
foreach ($r in $runs) {
    $slug = $r.Name -replace '[^\w]+', '_'
    $shots = Join-Path $OutDir $slug
    $log = Join-Path $OutDir "$slug.log"
    $err = Join-Path $OutDir "$slug.err.log"
    $a = @()
    if (-not $r.Win) { $a += "--headless" }
    if ($r.Fps) { $a += @("--fixed-fps", "$($r.Fps)") }
    $a += @("--path", "`"$Project`"", "-s", $r.Script)
    if ($r.Args.Count -gt 0) {
        $a += "--"
        foreach ($x in $r.Args) {
            if ($x -eq "{out}") { New-Item -ItemType Directory -Force $shots | Out-Null; $a += "`"$shots`"" } else { $a += $x }
        }
    }
    Write-Host -NoNewline ("  {0,-28} " -f $r.Name)
    $t0 = Get-Date
    $p = Start-Process -FilePath $Godot -ArgumentList ($a -join " ") -WorkingDirectory $Project -PassThru -NoNewWindow `
        -RedirectStandardOutput $log -RedirectStandardError $err
    $null = $p.Handle                    # (PowerShell 5.1 loses ExitCode without this)
    $timedOut = -not $p.WaitForExit($r.Timeout * 1000)
    if ($timedOut) { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null }   # (godot_console.exe runs godot.exe under it)
    $p.WaitForExit()                     # (no timeout: also waits for the redirected output to be written)
    $secs = ((Get-Date) - $t0).TotalSeconds
    $code = if ($timedOut) { $null } else { $p.ExitCode }
    $text = (Read-Shared $log) + "`n" + (Read-Shared $err)
    $lines = $text -split "`r?`n"
    $scriptErr = @($lines | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error' }).Count
    $engineErr = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^\s*(ERROR|USER ERROR):') { continue }
        $at = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { "" }    # (the "at:" line names the source)
        if ($lines[$i] -notmatch $Noise -and $at -notmatch $Noise) { $engineErr++ }
    }
    $warns = @($lines | Where-Object { $_ -match '^\s*(WARNING|USER WARNING):' }).Count
    $failLines = @($lines | Where-Object { $_ -match '^\s*(FAIL|TIMEOUT)\b|\bNOT DONE\b' })
    $failCount = 0
    foreach ($l in $lines) { if ($l -match '\b(FAILS|fails)\s+(\d+)') { $failCount = [math]::Max($failCount, [int]$Matches[2]) } }
    $note = ""
    if ($timedOut) { $status = "FAIL"; $note = "timeout $($r.Timeout) s" }
    elseif ($r.Skip -and $code -eq $r.Skip) { $status = "SKIP"; $note = "exit $code (nothing to test)" }
    elseif ($code -ne 0) { $status = "FAIL"; $note = if ($code -lt 0 -or $code -gt 255) { "crash (exit $code)" } else { "exit $code" } }
    elseif ($scriptErr -gt 0) { $status = "FAIL"; $note = "$scriptErr script errors" }
    elseif ($failLines.Count -gt 0) { $status = "FAIL"; $note = ($failLines[0].Trim()) }
    elseif ($failCount -gt 0) { $status = "FAIL"; $note = "fails $failCount" }
    elseif ($r.Expect -and $text -notmatch $r.Expect) { $status = "FAIL"; $note = "no '$($r.Expect)'" }
    elseif ($engineErr -gt 0) { $status = "WARN"; $note = "$engineErr engine errors" }
    else { $status = "PASS" }
    if ($note.Length -gt 70) { $note = $note.Substring(0, 70) + "..." }
    $color = @{ PASS = "Green"; WARN = "Yellow"; SKIP = "DarkGray"; FAIL = "Red" }[$status]
    Write-Host -ForegroundColor $color ("{0,-4} {1,6:N0}s  {2}" -f $status, $secs, $note)
    $results += [pscustomobject]@{
        Test = $r.Name; Status = $status; Exit = if ($timedOut) { "-" } else { "$code" }; Secs = [int]$secs
        Mode = (@($(if ($r.Win) { "window" } else { "headless" })) + @($(if ($r.Fps) { "fps$($r.Fps)" }))) -join " "
        Errors = $engineErr; Warnings = $warns; Note = $note
    }
}

Write-Host ""
$results | Format-Table -AutoSize Test, Status, Exit, Secs, Mode, Errors, Warnings, Note | Out-String -Width 200 | Write-Host
$n = @{}; foreach ($s in "PASS", "WARN", "SKIP", "FAIL") { $n[$s] = @($results | Where-Object Status -eq $s).Count }
$total = "PASS {0}  WARN {1}  SKIP {2}  FAIL {3}  of {4}" -f $n.PASS, $n.WARN, $n.SKIP, $n.FAIL, $results.Count
Write-Host $total

$md = @("# Test run $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "", "| test | status | exit | s | mode | errors | warnings | note |", "|---|---|---|---|---|---|---|---|")
foreach ($x in $results) { $md += "| $($x.Test) | $($x.Status) | $($x.Exit) | $($x.Secs) | $($x.Mode) | $($x.Errors) | $($x.Warnings) | $($x.Note -replace '\|', '/') |" }
$md += @("", $total, "", "Logs: $OutDir")
[IO.File]::WriteAllLines((Join-Path $OutDir "summary.md"), $md)
Write-Host "Summary: $(Join-Path $OutDir 'summary.md')"
exit $(if ($n.FAIL -gt 0) { 1 } else { 0 })
