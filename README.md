# vbridger-no-preview-patch

**Unofficial patch.** Stop VBridger from rendering its 3D preview model (saves GPU) while the
entire data pipeline — iFacialMocap / FaceMotion3D input -> VMC / VTube Studio / OSC output —
keeps working exactly as before.

[中文说明](README.zh-CN.md)

---

## Quick start

**Before you start**

- Close VBridger completely (tray icon included).
- Put `Patch-VBridgerNoPreview.ps1` and `VBridger-NoPreview.cmd` into the **VBridger folder**
  (the one containing `VBridger.exe` and `VBridger_Data\level2`). The script only looks for the
  game files in that folder.
- Windows with PowerShell 5.1 or newer (Windows 10/11 built-in is fine). No admin rights,
  no network access.

**Three steps**

1. Copy those two files into the VBridger folder.
2. Double-click `VBridger-NoPreview.cmd`. The menu is bilingual (Chinese / English):

   ```text
   ==========================================================
      VBridger 3D 预览补丁 / no-preview patch   -  unofficial
   ==========================================================

      1. 自检    check     - 只检查，不写入文件 / dry run
      2. 打补丁  apply     - 改 1 个字节，停止渲染 / patch it
      3. 回滚    rollback  - 用备份还原 level2 / restore it
      0. 退出    exit

   ==========================================================

   请输入编号 / enter number [0-3]:
   ```

3. Press `1` first (dry run) and check that the offsets and record classification match the
   table below. Then press `2` to apply.

After patching, the preview area of the VBridger window is expected to be empty/black — that is
the whole point. Tracking input, Send Face Found Status, VMC output (default port 39539) and the
VTube Studio WebSocket connection are unaffected.

Direct arguments also work, handy for shortcuts: `VBridger-NoPreview.cmd check|apply|restore`.

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
```

## Rollback

`-Restore` (or menu `3`) copies the newest `level2.bak_*` back over `level2` and re-verifies
that `BridgitFullbody` is active again. You can also delete the patched `level2` and rename a
backup to `level2`. Or use Steam: *Properties -> Installed Files -> Verify integrity of game
files*, which also restores the original.

## After a VBridger / Steam update

An update overwrites `level2`, so the patch is gone — just run it again. If the update ever
changes the scene layout, the script **refuses to write** and exits with code `1`, printing
every candidate record it found (length prefix, `m_Layer`, `m_Tag`, `m_IsActive`) so you can
see which field moved. It never writes blind.

## Exit codes

| code | meaning |
|------|---------|
| 0 | success, or nothing to do (already patched) |
| 1 | structure check failed — the game changed, nothing was written |
| 2 | environment error (wrong folder, VBridger running, unreadable file) |
| 3 | write or post-write verification failed — backup was restored automatically |

## Safety design

- **Structural validation first**: Unity version string, `level2` size, and for each target the
  record layout (4-byte length prefix matching the name length, `m_Layer == 0`, `m_Tag == 0`,
  `m_IsActive` in {0,1}). This rejects lookalike matches such as a `Mesh` that happens to share
  the name — `BridgitFullbody` appears twice in the file, only one is a real GameObject.
- **Automatic backup** `level2.bak_<yyyyMMdd-HHmmss>` before touching anything.
- **One byte written**, file length unchanged, no checksum in the file to invalidate.
- **Post-write verification** by re-parsing; on mismatch it restores the backup automatically
  and exits `3`.
- **Audit trail** in `VBridgerPatchState.json` (path, timestamp, Unity version, SHA-256 before).
- No network, no elevation, no service, no driver.

## What this patch does not do

- It does not remove the preview *objects* from the scene, only stops them from rendering.
- It does not reduce the window's resolution, and it does not affect `-batchmode -nographics`
  (that disables the whole GUI, and VBridger then needs a manual connect click every launch).
- It does not change tracking quality, calibration, or any output parameter.
- It does not redistribute, modify or reverse-distribute any file from VBridger.
  No game data is included in this repository — the tool only rewrites one byte on your machine.

## Disclaimer

Unofficial, community-made, not affiliated with or endorsed by PiPuProductions. Use at your
own risk; a backup is always created for you. If the author objects, this repository will be
taken down.

## License

MIT — see [LICENSE](LICENSE).
