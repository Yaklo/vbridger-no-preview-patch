#Requires -Version 5.1
<#
    Patch-VBridgerNoPreview.ps1
    ------------------------------------------------------------------
    Stops VBridger from rendering its 3D preview model (saves GPU) while
    keeping the whole data-forwarding pipeline (iFacialMocap / FaceMotion3D
    -> VMC / VTS / OSC) untouched.

    How: flips the GameObject m_IsActive flag (1 -> 0) of the preview model
         objects Bridgit / BridgitFullbody / bridgeface3 inside
         VBridger_Data\level2. The data scripts live on iFacialMocapTestObj,
         which this script never modifies.

    Safety:
      * Structural validation first (Unity version, record layout
        m_Layer / m_Tag / m_IsActive, byte fingerprint). If anything does
        not match, it aborts and writes nothing.
      * -Restore runs before that check, so rollback still works after an
        update. It picks the newest backup by the timestamp in its file name
        and refuses one that belongs to a different build unless -Force is
        given.
      * Rolling back (and the automatic rollback after a failed verification)
        deletes VBridgerPatchState.json, so a stale fingerprint cannot make the
        next -Restore look like a cross-version backup.
      * Automatic backup: level2 -> level2.bak_<timestamp>, restore with -Restore.
      * -DryRun checks only, never writes.
      * Post-write verification; on mismatch it rolls back automatically.

    Where: put this file inside the VBridger install folder, next to
           VBridger.exe (the folder that contains VBridger_Data\level2).
           It looks there only - no disk scanning. -InstallDir overrides.

    Usage (close VBridger first):
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -DryRun
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Restore

    Exit codes: 0 ok / nothing to do, 1 structure check failed,
                2 environment error, 3 write or verify failed.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = '',
    [switch]$DryRun,
    [switch]$Restore,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ExpectedUnityVersion = '2020.3.33f1'
$KeepActiveName       = 'iFacialMocapTestObj'
$ModelTargets = @(
    [pscustomobject]@{ Name = 'BridgitFullbody'; Desc = 'full-body preview model' },
    [pscustomobject]@{ Name = 'Bridgit';         Desc = 'half-body/head preview model' },
    [pscustomobject]@{ Name = 'bridgeface3';     Desc = 'alternate preview model' }
)

# ------------------------------------------------------------- output helpers
function Write-Head([string]$t) { Write-Host ''; Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan }
function Write-Ok([string]$t)   { Write-Host ('  [OK]   ' + $t) -ForegroundColor Green }
function Write-Note([string]$t) { Write-Host ('  [..]   ' + $t) -ForegroundColor Gray }
function Write-Warn2([string]$t){ Write-Host ('  [WARN] ' + $t) -ForegroundColor Yellow }
function Write-Err2([string]$t) { Write-Host ('  [FAIL] ' + $t) -ForegroundColor Red }

# ------------------------------------------------------------- locate install
# The scripts are meant to live in the VBridger folder itself, next to
# VBridger.exe. That folder is the only place they look by default - no
# registry reading, no Steam library scan, nothing machine specific.
function Resolve-VbRoot {
    param([string]$Given)
    $cands = New-Object System.Collections.ArrayList
    if ($Given) {
        [void]$cands.Add($Given)
    } elseif ($PSScriptRoot) {
        [void]$cands.Add($PSScriptRoot)
    }
    foreach ($c in $cands) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        if (Test-Path -LiteralPath $c -PathType Container) {
            if (Test-Path -LiteralPath (Join-Path $c 'VBridger_Data\level2') -PathType Leaf) {
                return (Resolve-Path -LiteralPath $c).Path
            }
        }
    }
    return $null
}

# ------------------------------------------------------------- byte helpers
# 1 byte -> 1 char decoder, so string indices equal byte offsets
function Get-Latin1String {
    param([byte[]]$Bytes)
    if (-not $script:Latin1Enc) {
        $script:Latin1Enc = $null
        try { $script:Latin1Enc = [System.Text.Encoding]::Latin1 } catch { }
        if (-not $script:Latin1Enc) { try { $script:Latin1Enc = [System.Text.Encoding]::GetEncoding(28591) } catch { } }
        if (-not $script:Latin1Enc) { $script:Latin1Enc = [System.Text.Encoding]::ASCII }
    }
    return $script:Latin1Enc.GetString($Bytes)
}

function Get-UnityVersionFrom {
    param([byte[]]$Bytes)
    $headLen = [Math]::Min(2048, $Bytes.Length)
    $head = New-Object byte[] $headLen
    [Array]::Copy($Bytes, 0, $head, 0, $headLen)
    $txt = Get-Latin1String -Bytes $head
    $m = [regex]::Match($txt, '20\d\d\.\d+\.\d+[abfp]\d+')
    if ($m.Success) { return $m.Value }
    return ''
}

# Find name records in a serialized file and tell real GameObject records
# apart from other objects (Mesh, renderer, etc.) that reuse the same name.
function Get-RecordCandidates {
    param([byte[]]$Bytes, [string]$Text, [string]$Name)

    $nameLen = $Name.Length
    $list = New-Object System.Collections.ArrayList
    $pos = 0
    while ($true) {
        $i = $Text.IndexOf($Name, $pos, [System.StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $pos = $i + 1
        if ($i -lt 8) { continue }

        $prefix = [BitConverter]::ToInt32($Bytes, $i - 4)    # m_Name length prefix
        $layer  = [BitConverter]::ToInt32($Bytes, $i - 8)    # m_Layer (int)
        $charsEnd = $i + $nameLen
        $pad = (4 - ($charsEnd % 4)) % 4                     # 4-byte alignment padding
        $tagOff = $charsEnd + $pad
        if (($tagOff + 3) -ge $Bytes.Length) { continue }
        $tag = [BitConverter]::ToUInt16($Bytes, $tagOff)      # m_Tag (u16)
        $activeOff = $tagOff + 2
        $active = [int]$Bytes[$activeOff]                    # m_IsActive (u8)

        $valid = ($prefix -eq $nameLen) -and ($layer -eq 0) -and ($tag -eq 0) -and (($active -eq 0) -or ($active -eq 1))

        [void]$list.Add([pscustomobject]@{
            Name         = $Name
            NameOffset   = $i
            PrefixOk     = ($prefix -eq $nameLen)
            Layer        = $layer
            Tag          = $tag
            Active       = $active
            ActiveOffset = $activeOff
            Valid        = $valid
        })
    }
    return $list.ToArray()
}

function Show-Candidates {
    param([object[]]$Cands)
    if (-not $Cands -or $Cands.Count -eq 0) { return }
    foreach ($c in $Cands) {
        $flag = 'IGNORED (not a GameObject record)'
        if ($c.Valid) { $flag = 'VALID GameObject record' }
        Write-Note ('  name offset ' + $c.NameOffset + '  lenPrefixOk=' + $c.PrefixOk + '  layer=' + $c.Layer + '  tag=' + $c.Tag + '  active=' + $c.Active + '  -> ' + $flag)
    }
}

# The state file only describes an applied patch. Once level2 is rolled back it
# is stale, and its Level2Before entry would make the next -Restore look like a
# cross-version backup. Drop it whenever the patch is undone.
function Remove-PatchState {
    if (-not $PSScriptRoot) { return }
    $sp = Join-Path $PSScriptRoot 'VBridgerPatchState.json'
    if (-not (Test-Path -LiteralPath $sp -PathType Leaf)) { return }
    try {
        Remove-Item -LiteralPath $sp -Force
        Write-Note 'patch state file removed (it described the patch that was just undone)'
    } catch {
        Write-Note '(could not remove VBridgerPatchState.json, harmless)'
    }
}

# ============================================================== main flow
$root = Resolve-VbRoot -Given $InstallDir
if (-not $root) {
    Write-Err2 'No VBridger install found in this script folder.'
    Write-Note ('script folder: ' + $PSScriptRoot)
    Write-Note 'Expected VBridger_Data\level2 inside that same folder.'
    Write-Note 'Fix: copy Patch-VBridgerNoPreview.ps1 and one launcher'
    Write-Note '     (VBridger-NoPreview.cmd, or VBridger-NoPreview-zh.cmd for a Chinese menu)'
    Write-Note '     into the VBridger folder (next to VBridger.exe), then run again.'
    Write-Note 'Or point at it once with: -InstallDir "<path to VBridger folder>"'
    exit 2
}

$dataDir = Join-Path $root 'VBridger_Data'
$level2  = Join-Path $dataDir 'level2'
$ggm     = Join-Path $dataDir 'globalgamemanagers'
$managed = Join-Path $dataDir 'Managed\Assembly-CSharp.dll'

Write-Head 'Environment'
Write-Ok ('install folder: ' + $root)
foreach ($f in @($level2, $ggm)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        Write-Err2 ('missing file: ' + $f)
        exit 2
    }
}
Write-Ok 'VBridger_Data\level2 and globalgamemanagers found'
if (-not (Test-Path -LiteralPath $managed -PathType Leaf)) {
    Write-Warn2 'Managed\Assembly-CSharp.dll not found - double-check this is the VBridger folder'
}

$proc = Get-Process -Name 'VBridger' -ErrorAction SilentlyContinue
if ($proc -and -not $Restore) {
    if (-not $Force) {
        Write-Err2 'VBridger is running. Exit VBridger completely first (or add -Force).'
        exit 2
    }
    Write-Warn2 'VBridger is running, continuing because -Force was given.'
}

$bytes = [System.IO.File]::ReadAllBytes($level2)
$origSize = $bytes.Length
$origHash = (Get-FileHash -LiteralPath $level2 -Algorithm SHA256).Hash
$text = Get-Latin1String -Bytes $bytes

$unityVer = Get-UnityVersionFrom -Bytes $bytes
$ggmVer   = Get-UnityVersionFrom -Bytes ([System.IO.File]::ReadAllBytes($ggm))

Write-Head 'Version and fingerprint'
Write-Note ('level2 size: ' + $origSize + ' bytes')
Write-Note ('Unity version in level2: ' + $(if ($unityVer) { $unityVer } else { '(not detected)' }))
Write-Note ('Unity version in globalgamemanagers: ' + $(if ($ggmVer) { $ggmVer } else { '(not detected)' }))
Write-Note ('level2 SHA256: ' + $origHash)

$verWarn = $false
if ($ggmVer -and ($ggmVer -ne $ExpectedUnityVersion)) { $verWarn = $true }
if ($unityVer -and ($unityVer -ne $ExpectedUnityVersion)) { $verWarn = $true }
if ($verWarn) {
    Write-Warn2 ('Unity version differs from the version this script targets (' + $ExpectedUnityVersion + ').')
    Write-Warn2 'VBridger was probably updated. Record layout is re-validated below; if it does not match, nothing is written.'
} else {
    Write-Ok ('Unity version matches: ' + $ExpectedUnityVersion)
}

# ---- restore mode
# Handled before the structure validation on purpose: after a VBridger update
# the record layout may no longer match, and rolling back is exactly what you
# need in that situation.
if ($Restore) {
    Write-Head 'Restore'
    # Newest backup by the timestamp in its NAME. Copy-Item keeps the source
    # file's LastWriteTime, so file times are not a reliable ordering key.
    $baks = @(Get-ChildItem -LiteralPath $dataDir -Filter 'level2.bak_*' -File | Sort-Object -Property Name -Descending)
    if ($baks.Count -eq 0) {
        Write-Err2 ('no level2.bak_* backup in ' + $dataDir + ', nothing to restore.')
        exit 2
    }
    $b = $baks[0]
    Write-Note ('using backup: ' + $b.Name + '  (' + $b.Length + ' bytes)')
    if ($proc -and -not $Force) {
        Write-Err2 'VBridger is running. Exit it first (or add -Force).'
        exit 2
    }

    $bHash = (Get-FileHash -LiteralPath $b.FullName -Algorithm SHA256).Hash
    if ($bHash -eq $origHash) {
        Write-Ok 'level2 already matches this backup, nothing to restore.'
        Remove-PatchState
        exit 0
    }

    # Does this backup belong to the build that is installed right now? A
    # Steam update leaves the old backups behind, and putting a previous
    # version's level2 over a newer one would break the install.
    $suspect = New-Object System.Collections.ArrayList
    $bBytes = [System.IO.File]::ReadAllBytes($b.FullName)
    $bVer   = Get-UnityVersionFrom -Bytes $bBytes
    if ($b.Length -ne $origSize) {
        [void]$suspect.Add('size differs: backup ' + $b.Length + ' bytes, current level2 ' + $origSize + ' bytes')
    }
    if ($bVer -and $ggmVer -and ($bVer -ne $ggmVer)) {
        [void]$suspect.Add('Unity version differs: backup ' + $bVer + ', installed ' + $ggmVer)
    }
    if ($PSScriptRoot) {
        $statePath = Join-Path $PSScriptRoot 'VBridgerPatchState.json'
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            try {
                $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                if ($st.Level2Before -and $st.Level2Before.Sha256 -and ($st.Level2Before.Sha256 -ne $bHash)) {
                    [void]$suspect.Add('backup is not the original recorded in VBridgerPatchState.json')
                }
            } catch {
                Write-Note '(patch state file unreadable, cross-check skipped)'
            }
        }
    }
    if ($suspect.Count -gt 0) {
        foreach ($s in $suspect) { Write-Warn2 $s }
        if (-not $Force) {
            Write-Err2 'This backup may come from a different VBridger version. Nothing was restored.'
            Write-Note 'level2 was left untouched. If you really want this backup, add -Force.'
            exit 1
        }
        Write-Warn2 'Continuing anyway because -Force was given.'
    }

    Copy-Item -LiteralPath $b.FullName -Destination $level2 -Force
    Remove-PatchState
    $rAfter = [System.IO.File]::ReadAllBytes($level2)
    $rText = Get-Latin1String -Bytes $rAfter
    $chk = @(Get-RecordCandidates -Bytes $rAfter -Text $rText -Name 'BridgitFullbody' | Where-Object { $_.Valid })
    if ($chk.Count -eq 1 -and $chk[0].Active -eq 1) {
        Write-Ok 'Restored: BridgitFullbody active=1, preview is back.'
        exit 0
    }
    if ($chk.Count -eq 1) {
        Write-Warn2 ('Restored, but BridgitFullbody active=' + $chk[0].Active + '. Check that this backup is an untouched original.')
    } else {
        Write-Warn2 'Restored, but the preview object could not be located in the backup.'
    }
    exit 0
}

# ---- structural validation
Write-Head 'Structure check (locate preview model GameObjects)'
$plan = New-Object System.Collections.ArrayList
$structFail = $false

foreach ($t in $ModelTargets) {
    $cands = @(Get-RecordCandidates -Bytes $bytes -Text $text -Name $t.Name)
    Write-Note ('target "' + $t.Name + '" (' + $t.Desc + '): name appears ' + $cands.Count + ' time(s)')
    Show-Candidates -Cands $cands

    $valid = @($cands | Where-Object { $_.Valid })
    if ($valid.Count -eq 0) {
        Write-Err2 ('no valid GameObject record for "' + $t.Name + '" - the file layout differs from what this script expects.')
        $structFail = $true
        continue
    }
    if ($valid.Count -gt 1) {
        Write-Err2 ('"' + $t.Name + '" matched ' + $valid.Count + ' valid records, cannot decide which one to patch. Aborted.')
        $structFail = $true
        continue
    }
    [void]$plan.Add([pscustomobject]@{
        Name   = $t.Name
        Desc   = $t.Desc
        Offset = $valid[0].ActiveOffset
        Active = $valid[0].Active
    })
}

# data-path root object must stay active; never touched
$keepCands = @(Get-RecordCandidates -Bytes $bytes -Text $text -Name $KeepActiveName | Where-Object { $_.Valid })
Write-Note ('data-path root object "' + $KeepActiveName + '": ' + $keepCands.Count + ' valid record(s)')
if ($keepCands.Count -eq 1) {
    Write-Ok ('"' + $KeepActiveName + '" active=' + $keepCands[0].Active + ' (never modified by this script)')
    if ($keepCands[0].Active -ne 1) { Write-Warn2 'It is already inactive - data forwarding may not work at all.' }
} else {
    Write-Warn2 'Could not uniquely locate the data-path root object; informational only.'
}

if ($structFail) {
    Write-Head 'Result'
    Write-Err2 'Structure check failed. Nothing was written.'
    Write-Note 'Possible causes: VBridger changed its scene structure/names, or changed packaging format.'
    Write-Note 'Send VBridger_Data\level2 plus globalgamemanagers back for re-analysis,'
    Write-Note 'or restore a previous backup with -Restore.'
    exit 1
}

# ---- plan
Write-Head 'Plan'
$todo = @($plan | Where-Object { $_.Active -eq 1 })
foreach ($p in $plan) {
    $act = 'already 0, nothing to do'
    if ($p.Active -eq 1) { $act = 'will be set to 0 (rendering stops)' }
    Write-Note ('  ' + $p.Name.PadRight(16) + ' active offset ' + $p.Offset + '  current=' + $p.Active + '  ' + $act)
}

if ($todo.Count -eq 0) {
    Write-Head 'Result'
    Write-Ok 'All preview models are already inactive, nothing to do (already patched?).'
    exit 0
}

if ($DryRun) {
    Write-Head 'Result (-DryRun, nothing written)'
    Write-Ok ('Structure check passed. ' + $todo.Count + ' byte(s) would be changed.')
    Write-Note 'Run again without -DryRun to apply the patch.'
    exit 0
}

# ---- apply
Write-Head 'Apply patch'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = $level2 + '.bak_' + $stamp
Copy-Item -LiteralPath $level2 -Destination $backup -Force
Write-Ok ('backup created: ' + $backup)

$new = New-Object byte[] $origSize
[Array]::Copy($bytes, 0, $new, 0, $origSize)
foreach ($p in $todo) { $new[$p.Offset] = 0 }

try {
    [System.IO.File]::WriteAllBytes($level2, $new)
} catch {
    Write-Err2 ('write failed: ' + $_.Exception.Message)
    Write-Note ('original is backed up at ' + $backup + ' (-Restore also works)')
    exit 3
}

# ---- verify
Write-Head 'Verify'
$after = [System.IO.File]::ReadAllBytes($level2)
$afterText = Get-Latin1String -Bytes $after
$okAll = $true
if ($after.Length -ne $origSize) {
    Write-Err2 ('file size changed: ' + $origSize + ' -> ' + $after.Length)
    $okAll = $false
}
foreach ($p in $plan) {
    $chk = @(Get-RecordCandidates -Bytes $after -Text $afterText -Name $p.Name | Where-Object { $_.Valid })
    if ($chk.Count -eq 1) {
        if ($chk[0].Active -eq 0) {
            Write-Ok ($p.Name + ' active=0 (rendering stopped)')
        } else {
            Write-Err2 ($p.Name + ' active=' + $chk[0].Active + ', patch did not take effect')
            $okAll = $false
        }
    } else {
        Write-Err2 ($p.Name + ': could not locate record during verification')
        $okAll = $false
    }
}
$keepAfter = @(Get-RecordCandidates -Bytes $after -Text $afterText -Name $KeepActiveName | Where-Object { $_.Valid })
if ($keepAfter.Count -eq 1 -and $keepAfter[0].Active -eq 1) {
    Write-Ok ('data-path root object ' + $KeepActiveName + ' still active=1')
} else {
    Write-Warn2 'data-path root object looks wrong, please -Restore and report.'
}

if (-not $okAll) {
    Write-Err2 'Verification failed, rolling back...'
    Copy-Item -LiteralPath $backup -Destination $level2 -Force
    Remove-PatchState
    Write-Note ('rolled back to ' + $backup)
    exit 3
}

# remember fingerprint so a later run can tell whether VBridger was updated
try {
    if ($PSScriptRoot) {
        $statePath = Join-Path $PSScriptRoot 'VBridgerPatchState.json'
        $state = [pscustomobject]@{
            PatchedAt    = (Get-Date).ToString('s')
            InstallDir   = $root
            UnityVersion = $ggmVer
            Level2Before = [pscustomobject]@{ Size = $origSize; Sha256 = $origHash }
            PatchedNames = @($todo | ForEach-Object { $_.Name })
        }
        ($state | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $statePath -Encoding UTF8
        Write-Note ('patch state saved: ' + $statePath)
    }
} catch {
    Write-Note '(could not save patch state file, patch itself is fine)'
}

Write-Head 'Done'
Write-Ok 'Patch applied: the 3D preview model no longer renders; the data pipeline is unchanged.'
Write-Note 'Expected: empty/black preview panel in VBridger, while iFacialMocap input, VMC (default 39539) and VTS output keep working.'
Write-Note 'A Steam update overwrites this change - just run this script again afterwards (structure is re-validated).'
Write-Note ('Rollback: -Restore  (backup: ' + (Split-Path $backup -Leaf) + ')')
exit 0
