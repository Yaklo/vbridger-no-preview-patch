#Requires -Version 5.1
<#
    Patch-VBridgerNoPreview.ps1
    ------------------------------------------------------------------
    Stops VBridger from rendering its 3D preview model (saves GPU) and
    leaves the data pipeline alone: it only clears the m_IsActive flag of
    the preview GameObjects inside VBridger_Data\level2. The data scripts
    sit on iFacialMocapTestObj, which is never modified, so iFacialMocap
    input keeps reaching VMC / VTS exactly as before.

    Usage - put this file in the VBridger folder (next to VBridger.exe):
      ... -Check      report what would change, write nothing
      ...             apply the patch (a backup copy is made first)
      ... -Restore    copy the newest level2.bak_* back over level2

    Exit codes: 0 ok / nothing to do, 1 the file is not the level2 this
                script knows (nothing written), 2 environment problem,
                3 write or copy failed (the backup is kept).
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'

$Targets  = @('BridgitFullbody', 'Bridgit', 'bridgeface3')
$KeepName = 'iFacialMocapTestObj'

function Say([string]$tag, [string]$msg) {
    $c = 'Gray'
    if ($tag -eq 'OK')   { $c = 'Green' }
    if ($tag -eq 'WARN') { $c = 'Yellow' }
    if ($tag -eq 'FAIL') { $c = 'Red' }
    Write-Host ('  [' + $tag + '] ' + $msg) -ForegroundColor $c
}

# A real GameObject record inside level2 looks like this:
#   [m_Layer:int32=0][nameLen:int32]["Name"][pad to 4][m_Tag:uint16=0][m_IsActive:uint8]
# The same name also appears on other objects (a Mesh, a renderer), so the
# layout is checked instead of trusting the first hit. Returns @{Offset;Active}
# for the one record that matches, or $null when there is none or several.
function Find-IsActive {
    param([byte[]]$Bytes, [string]$Text, [string]$Name)
    $nameLen = $Name.Length
    $hits = @()
    $pos = 0
    while ($true) {
        $i = $Text.IndexOf($Name, $pos, [System.StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $pos = $i + 1
        if ($i -lt 8) { continue }
        if ([BitConverter]::ToInt32($Bytes, $i - 4) -ne $nameLen) { continue }  # length prefix
        if ([BitConverter]::ToInt32($Bytes, $i - 8) -ne 0) { continue }         # m_Layer
        $charsEnd = $i + $nameLen
        $tagOff = $charsEnd + ((4 - ($charsEnd % 4)) % 4)
        if (($tagOff + 2) -ge $Bytes.Length) { continue }
        if ([BitConverter]::ToUInt16($Bytes, $tagOff) -ne 0) { continue }       # m_Tag
        $active = [int]$Bytes[$tagOff + 2]
        if ($active -gt 1) { continue }                                        # m_IsActive
        $hits += @{ Offset = $tagOff + 2; Active = $active }
    }
    if ($hits.Count -eq 1) { return $hits[0] }
    return $null
}

$data   = Join-Path $PSScriptRoot 'VBridger_Data'
$level2 = Join-Path $data 'level2'
$enc    = [System.Text.Encoding]::GetEncoding(28591)

Write-Host ''
Write-Host '=== VBridger no-preview patch ===' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $data -PathType Container)) {
    Say 'FAIL' ('not found: ' + $data)
    Say '..' 'Put this script in the VBridger folder (next to VBridger.exe).'
    exit 2
}

# ---- rollback
if ($Restore) {
    $baks = @(Get-ChildItem -LiteralPath $data -Filter 'level2.bak_*' -File | Sort-Object -Property Name -Descending)
    if ($baks.Count -eq 0) {
        Say 'FAIL' ('no level2.bak_* backup in ' + $data)
        exit 2
    }
    $b = $baks[0]
    Say '..' ('backup: ' + $b.Name)
    if (-not (Test-Path -LiteralPath $level2 -PathType Leaf)) {
        Say '..' 'level2 is missing, it will be recreated from this backup'
    }

    # look inside the backup before overwriting anything - a stray file with
    # the right name must not be able to destroy the install
    try {
        $bb = [System.IO.File]::ReadAllBytes($b.FullName)
    } catch {
        Say 'FAIL' ('cannot read the backup: ' + $_.Exception.Message)
        exit 2
    }
    $bt = $enc.GetString($bb)
    $found = 0
    foreach ($n in $Targets) { if (Find-IsActive -Bytes $bb -Text $bt -Name $n) { $found++ } }
    if ($found -lt $Targets.Count) {
        Say 'FAIL' 'this backup does not look like the level2 this script knows. Nothing was written.'
        Say '..' 'Delete that file, copy another level2.bak_* back by hand, or repair with Steam.'
        exit 1
    }

    if ($Check) {
        Say 'OK' ('a real run would copy ' + $b.Name + ' over level2')
        exit 0
    }
    try {
        Copy-Item -LiteralPath $b.FullName -Destination $level2 -Force
        $same = (Get-FileHash -LiteralPath $level2).Hash -eq (Get-FileHash -LiteralPath $b.FullName).Hash
    } catch {
        Say 'FAIL' ('copy failed: ' + $_.Exception.Message)
        exit 3
    }
    if (-not $same) {
        Say 'FAIL' 'the copied file does not match the backup'
        exit 3
    }
    Say 'OK' 'restored: the 3D preview model is back'
    exit 0
}

if (-not (Test-Path -LiteralPath $level2 -PathType Leaf)) {
    Say 'FAIL' ('not found: ' + $level2)
    Say '..' 'Nothing to patch here. Run -Restore to put a backup back.'
    exit 2
}

# ---- locate the preview records
$bytes = [System.IO.File]::ReadAllBytes($level2)
$text  = $enc.GetString($bytes)

$plan = @()
$bad  = $false
foreach ($name in $Targets) {
    $r = Find-IsActive -Bytes $bytes -Text $text -Name $name
    if (-not $r) {
        Say 'FAIL' ('cannot identify a single GameObject record for "' + $name + '"')
        $bad = $true
        continue
    }
    $plan += @{ Name = $name; Offset = $r.Offset; Active = $r.Active }
}
if ($bad) {
    Say 'FAIL' 'level2 does not look like the build this script knows. Nothing was written.'
    Say '..' 'Repair it with Steam (Properties - Installed Files - Verify integrity),'
    Say '..' 'or put a level2.bak_* file back by hand.'
    exit 1
}

foreach ($p in $plan) {
    $state = 'active=1, preview renders'
    if ($p.Active -eq 0) { $state = 'active=0, already hidden' }
    Say '..' ($p.Name.PadRight(16) + ' ' + $state)
}
$keep = Find-IsActive -Bytes $bytes -Text $text -Name $KeepName
if ($keep) { Say '..' ($KeepName + ' active=' + $keep.Active + ' (data path, untouched)') }

$todo = @($plan | Where-Object { $_.Active -eq 1 })
if ($todo.Count -eq 0) { Say 'OK' 'already patched, nothing to do'; exit 0 }
if ($Check) { Say 'OK' ([string]$todo.Count + ' byte(s) would be changed by a real run'); exit 0 }

# ---- apply
$backup = $level2 + '.bak_' + (Get-Date -Format 'yyyyMMdd-HHmmss')
try { Copy-Item -LiteralPath $level2 -Destination $backup -Force }
catch { Say 'FAIL' ('backup failed: ' + $_.Exception.Message); exit 3 }
Say '..' ('backup: ' + (Split-Path $backup -Leaf))

$new = [byte[]]$bytes.Clone()
foreach ($p in $todo) { $new[$p.Offset] = 0 }
try { [System.IO.File]::WriteAllBytes($level2, $new) }
catch {
    Say 'FAIL' ('write failed: ' + $_.Exception.Message + ' - is VBridger still running?')
    Say '..' ('backup kept: ' + (Split-Path $backup -Leaf))
    exit 3
}

# ---- verify
try {
    $after     = [System.IO.File]::ReadAllBytes($level2)
    $afterText = $enc.GetString($after)
} catch {
    Say 'FAIL' ('cannot read level2 back: ' + $_.Exception.Message)
    Say '..' ('backup kept: ' + (Split-Path $backup -Leaf))
    exit 3
}
$ok = ($after.Length -eq $bytes.Length)
foreach ($p in $todo) {
    $r = Find-IsActive -Bytes $after -Text $afterText -Name $p.Name
    if (-not $r -or $r.Active -ne 0) { $ok = $false }
}
if (-not $ok) {
    Say 'FAIL' 'verification failed, copying the backup back'
    try { Copy-Item -LiteralPath $backup -Destination $level2 -Force }
    catch { Say 'FAIL' ('could not copy the backup back: ' + $_.Exception.Message) }
    Say '..' ('backup kept: ' + (Split-Path $backup -Leaf))
    exit 3
}

Say 'OK' 'patched: the 3D preview model no longer renders, the data pipeline is unchanged'
Say '..' ('rollback: -Restore  (backup: ' + (Split-Path $backup -Leaf) + ')')
exit 0
