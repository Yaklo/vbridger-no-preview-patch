# vbridger-no-preview-patch

**Unofficial patch.** Stop VBridger from rendering its 3D preview model (saves GPU) while the
entire data pipeline — iFacialMocap / FaceMotion3D input -> VMC / VTube Studio / OSC output —
keeps working exactly as before.

[中文说明](README.zh-CN.md)

---

## Quick start

**Before you start**

- Close VBridger completely (tray icon included).
- Put `Patch-VBridgerNoPreview.ps1` and one of the two `.cmd` launchers into the **VBridger
  folder** (the one containing `VBridger.exe` and `VBridger_Data\level2`). The script only
  looks for the VBridger files in that folder.
- Windows with PowerShell 5.1 or newer (Windows 10/11 built-in is fine). No admin rights,
  no network access.

**Three steps**

1. Copy `Patch-VBridgerNoPreview.ps1` and `VBridger-NoPreview.cmd` into the VBridger folder.
2. Double-click `VBridger-NoPreview.cmd`. It is pure ASCII, so it cannot be garbled by any
   console code page:

   ```text
   ==========================================================
      VBridger no-preview patch   -  unofficial
   ==========================================================

      1. check     - dry run, writes nothing
      2. apply     - flip 1 byte, stop rendering
      3. rollback  - restore level2 from the newest backup
      0. exit

      Chinese menu: VBridger-NoPreview-zh.cmd
   ==========================================================

   enter number [0-3]:
   ```

3. Press `1` first (dry run) and check that the offsets and record classification match the
   table below. Then press `2` to apply.

After patching, the preview area of the VBridger window is expected to be empty/black — that is
the whole point. Tracking input, Send Face Found Status, VMC output (default port 39539) and the
VTube Studio WebSocket connection are unaffected.

**Which launcher to use**

| file | menu | encoding | use it when |
|------|------|----------|-------------|
| `VBridger-NoPreview.cmd` | English | pure ASCII | any locale, any code page — cannot be garbled |
| `VBridger-NoPreview-zh.cmd` | Chinese + English | GBK | Chinese Windows (code page 936) |

Both do exactly the same thing and call the same `Patch-VBridgerNoPreview.ps1`. The GBK file only
displays correctly on code page 936, which is why the English one exists as a pure-ASCII twin;
if you launch the Chinese one on a non-936 console it warns you first and points you at
`VBridger-NoPreview.cmd`, so you are never stuck with a screen full of mojibake.

Both accept direct arguments, handy for shortcuts, scheduled tasks and batch files:
`<file> check|apply|restore`. In that mode the launcher runs the action once, skips the
confirmation prompt, exits with the script's own exit code and never drops into the menu.

## Why

VBridger's actual job is to receive face-tracking data from a phone and forward it to other
software. The 3D character in the window is only a visual aid, but it stays fully rigged and
skinned (dozens of blend shapes) and renders every frame, forever. If you never look at it,
that is pure waste: GPU time, heat, fan noise.

There is no setting to turn the preview off (the "face" toggle in the gear overlay is a temporary
switch, it is not persisted, and the preview comes back on every launch). This patch disables the
preview model objects in the Unity scene, so nothing gets drawn, while every script that receives
and forwards data is untouched.

## What it changes

Exactly **one byte** in `VBridger_Data\level2` — the `m_IsActive` flag of the full-body
preview model `BridgitFullbody` (1 -> 0). The other two preview objects are already inactive
in the shipped build; the script confirms that and leaves them alone.

| object                | role                    | name offset | `m_IsActive` byte | shipped | after patch |
|-----------------------|-------------------------|-------------|--------------------|---------|-------------|
| `BridgitFullbody`      | full-body preview model | 110820      | **110838**         | 1       | **0**       |
| `Bridgit`              | head/half-body preview  | 108272      | 108282             | 0       | 0 (untouched) |
| `bridgeface3`          | alternate preview mesh  | 108112      | 108126             | 0       | 0 (untouched) |
| `iFacialMocapTestObj`   | **data pipeline root**  | 108224      | 108246             | 1       | 1 (**never touched**) |

The receive/forward scripts (`UnityRecieve_iFacialMocapCustom`, `UnityRecieve_FACEMOTION3D`,
`SendShape`, `GetShapeKeys`, `VMCSend`, `uOscClient`, `VTSWebSocket`) all live on
`iFacialMocapTestObj`, which this patch never modifies. Nothing in the assembly references the
preview objects, so disabling them cannot cause a null reference at runtime.

Verified against the build whose `level2` is 412672 bytes with SHA-256
`2F177FB02D57D1600E4DF65A13E5E92BAE951AC9181D4186FA61B9A7396E9B52`
(Unity `2020.3.33f1`, Mono backend).

## Command line usage

If you prefer not to use the menu:

```powershell
# check only, never writes
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -DryRun

# apply (creates level2.bak_<timestamp> first, then verifies)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1

# roll back
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Restore

# run the script from anywhere, without copying it into the VBridger folder
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -InstallDir "D:\Steam\steamapps\common\VBridger" -DryRun
```

| parameter | what it does |
|-----------|--------------|
| `-DryRun` | check only, write nothing; combined with `-Restore` it reports what a rollback would do instead of overwriting `level2`; works even while VBridger is open |
| `-Restore` | copy the newest `level2.bak_*` back over `level2` |
| `-InstallDir <path>` | point at the VBridger folder instead of looking next to the script, so the script can live anywhere; the path is recorded in `VBridgerPatchState.json` |
| `-Force` | proceed while VBridger is running, and accept a backup that looks like it belongs to a different build |

## Rollback

`-Restore` (or menu `3`) copies the newest `level2.bak_*` back over `level2` and re-verifies
that `BridgitFullbody` is active again. Close VBridger first, otherwise the rollback is refused
the same way an apply is (exit `2`; `-Force` overrides). Add `-DryRun` to see which backup it
would use and whether it would accept it, without writing anything.

You can also delete the patched `level2` and rename a backup to `level2`. Or use Steam:
*Properties -> Installed Files -> Verify integrity of files*, which also restores the original.

Old `level2.bak_*` files can simply be deleted - only the newest one is ever used, so keeping
one or two is enough.

## After a VBridger / Steam update

An update overwrites `level2`, so the patch is gone — just run it again. If the update ever
changes the scene layout, the script **refuses to write** and exits with code `1`, printing
every candidate record it found (length prefix, `m_Layer`, `m_Tag`, `m_IsActive`) so you can
see which field moved. It never writes blind.

## Exit codes

| code | meaning |
|------|---------|
| 0 | success, or nothing to do (already patched) |
| 1 | structure check failed, or a restore was refused — nothing was written |
| 2 | environment error (wrong folder, VBridger running, unreadable file) |
| 3 | write, backup copy or post-write verification failed — `level2` was left untouched or restored automatically |

## Safety design

- **Structural validation first**: the Unity version string, and for each target the record
  layout (4-byte length prefix matching the name length, `m_Layer == 0`, `m_Tag == 0`,
  `m_IsActive` in {0,1}). This rejects lookalike matches such as a `Mesh` that happens to share
  the name — `BridgitFullbody` appears twice in the file, only one is a real GameObject.
- **Automatic backup** `level2.bak_<yyyyMMdd-HHmmss>` before touching anything, hash-checked
  against `level2` right after the copy.
- **Atomic writes**: `level2` is written through a temporary file and swapped in with
  `File::Replace`, so an interrupted run cannot leave a half-written file behind.
  On filesystems without replace support (or if the file is held open) the swap falls back
  to a plain copy.
- **One byte written**, file length unchanged, no checksum in the file to invalidate.
- **Post-write verification** by re-parsing; on mismatch it restores the backup automatically
  and exits `3`.
- **Rollback does not depend on the structure check**: `-Restore` runs before it, so it still
  works after an update. The newest backup is chosen by the timestamp in its file name, and a
  backup that does not match the installed build is refused unless you pass `-Force`.
  "Match" is checked byte-for-byte: the installed `level2` must be exactly that backup with the
  preview flags cleared, so a file replaced by an update is caught even when its size and Unity
  version happen to be identical. Size, Unity version and the SHA-256 recorded in
  `VBridgerPatchState.json` are checked as well.
- **Audit trail** in `VBridger_Data\VBridgerPatchState.json` (path, timestamp, Unity version,
  SHA-256 before). It follows the install rather than the script, so `-InstallDir` and a second
  copy of the script still see the same record.
- **Rollback cleans up after itself**: a successful `-Restore`, and the automatic rollback after
  a failed verification, delete `VBridgerPatchState.json` - it describes a patch that no longer
  exists, and a leftover `Level2Before` hash would make the next rollback look suspicious.
- No network, no elevation, no service, no driver.

## What this patch does not do

- It does not remove the preview *objects* from the scene, only stops them from rendering.
- It does not reduce the window's resolution, and it does not affect `-batchmode -nographics`
  (that disables the whole GUI, and VBridger then needs a manual connect click every launch).
- It does not change tracking quality, calibration, or any output parameter.
- It does not redistribute, modify or reverse-distribute any file from VBridger.
  No VBridger files are included in this repository — the tool only rewrites one byte on your
  machine.

## Disclaimer

Unofficial, community-made, not affiliated with or endorsed by PiPuProductions. Use at your
own risk; a backup is always created for you. If the author objects, this repository will be
taken down.

## License

MIT — see [LICENSE](LICENSE).
