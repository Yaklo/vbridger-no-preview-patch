# vbridger-no-preview-patch

**Unofficial patch.** Stop VBridger from rendering its 3D preview model (saves GPU) while the
entire data pipeline — iFacialMocap / FaceMotion3D input -> VMC / VTube Studio / OSC output —
keeps working exactly as before.

[中文说明](README.zh-CN.md)

---

## Quick start

1. Close VBridger (tray icon included).
2. Copy `Patch-VBridgerNoPreview.ps1` and `VBridger-NoPreview.cmd` into the **VBridger folder** —
   the one containing `VBridger.exe` and `VBridger_Data\level2`. The script only looks there.
3. Double-click `VBridger-NoPreview.cmd`:

   ```text
   ==========================================================
      VBridger no-preview patch   -  unofficial
   ==========================================================

      1. check     - read only, writes nothing
      2. apply     - back up level2, flip 1 byte
      3. rollback  - restore level2 from the newest backup
      0. exit

      Chinese menu: VBridger-NoPreview-zh.cmd
   ==========================================================

   enter number [0-3]:
   ```

4. Press `1` to see what would change, then `2`.

After patching, the preview area of the VBridger window is empty/black — that is the whole point.
Tracking input, Send Face Found Status, VMC output (default port 39539) and the VTube Studio
WebSocket connection are unaffected.

Windows PowerShell 5.1 or newer is enough (Windows 10/11 built-in). No admin rights, no network.

**Which launcher**

| file | menu | encoding |
|------|------|----------|
| `VBridger-NoPreview.cmd` | English | pure ASCII — cannot be garbled by any code page |
| `VBridger-NoPreview-zh.cmd` | Chinese + English | GBK (code page 936); warns you first on other code pages |

Both call the same script and accept `check` / `apply` / `restore` as a direct argument, which
runs that one action, skips the confirmation prompt and exits with the script's exit code.

## Why

VBridger's job is to receive face-tracking data from a phone and forward it to other software. The
3D character in the window is only a visual aid, but it stays fully rigged and skinned (dozens of
blend shapes) and renders every frame. If you never look at it, that is pure GPU waste.

There is no way to turn the 3D preview off in the software itself — the UI has no such option, so
the model is rendered for as long as VBridger runs. This patch disables the preview objects in the
Unity scene, so nothing gets drawn, while every script that receives and forwards data is
untouched.

## What it changes

Exactly **one byte** in `VBridger_Data\level2` — the `m_IsActive` flag of the full-body preview
model `BridgitFullbody` (1 -> 0). The other two preview objects are already inactive in the
shipped build; the script sees that and leaves them alone.

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

## The three actions

| menu | command line | what it does |
|------|--------------|--------------|
| 1 | `-Check` | reads `level2`, prints how many bytes a real run would change. Writes nothing, creates no backup. |
| 2 | *(no argument)* | copies `level2` to `level2.bak_<yyyyMMdd-HHmmss>`, clears the flags, verifies the result byte by byte. On mismatch it puts the backup back and exits `3`. |
| 3 | `-Restore` | copies the newest `level2.bak_*` back over `level2` and verifies it. Add `-Check` to preview it. |

```powershell
# check only
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Check

# apply, then roll back
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Restore
```

| code | meaning |
|------|---------|
| 0 | success, or nothing to do (already patched / nothing to restore) |
| 1 | a file does not look like the `level2` this script knows (the install, or the backup it would restore) — nothing was written |
| 2 | environment problem (script not next to `VBridger_Data`, file missing, unreadable) |
| 3 | write or copy failed, or the result did not verify — the backup is still there |

## Safety

- **Structure check before any write**: for each target the record must have a 4-byte length
  prefix matching the name length, `m_Layer == 0`, `m_Tag == 0` and `m_IsActive` in {0,1}, and
  exactly one such record must exist. That rejects lookalikes — `BridgitFullbody` appears twice
  in the file, only one of them is a real GameObject. If anything does not add up, the script
  writes nothing and exits `1`.
- **Backup first**: `level2.bak_<timestamp>` is copied and compared against the original before
  the patch is written.
- **One byte written**, file length unchanged, no checksum inside the file to invalidate.
- **Verification after writing**; a failed one restores the backup and exits `3`.
- No network, no elevation, no service, no driver, and no state file — the newest backup next to
  `level2` is all the bookkeeping there is. If a rollback copies the wrong one, Steam can always
  repair the install.

## After a VBridger / Steam update

An update overwrites `level2`, so the patch is gone — run action `2` again. If the update also
changes the scene layout, the script refuses to write (exit `1`) instead of guessing.

Keep one or two `level2.bak_*` files around; older ones can be deleted, only the newest is used.
The newest backup is inspected before it is copied: if it does not look like a `level2`, the
rollback refuses and writes nothing, so a stray file with the right name cannot destroy the install.
To roll back without the script: rename a backup to `level2`, or use Steam —
*Properties -> Installed Files -> Verify integrity of files*.

## What this patch does not do

- It does not remove the preview objects from the scene, only stops them from rendering.
- It does not touch the window, and it is not the same as `-batchmode -nographics` (that kills the
  whole GUI, so VBridger then needs a manual connect click every launch).
- It does not change tracking quality, calibration, or any output parameter.
- It does not redistribute or modify any VBridger file. Nothing from VBridger is included in this
  repository — the tool only rewrites one byte on your machine.

## Disclaimer

Unofficial, community-made, not affiliated with or endorsed by PiPuProductions. Use at your own
risk; a backup is always created for you. If the author objects, this repository will be taken
down.

## License

MIT — see [LICENSE](LICENSE).
