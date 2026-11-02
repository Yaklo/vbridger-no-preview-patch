# vbridger-no-preview-patch

**非官方补丁。** 让 VBridger 不再渲染窗口里的 3D 预览模型（省 GPU），而数据链路
—— iFacialMocap / FaceMotion3D 输入 → VMC / VTube Studio / OSC 输出 —— 完全不受影响。

[English](README.md)

---

## 快速开始

**前置条件**

- 完全退出 VBridger（托盘、任务栏都不要留）。
- 把 `Patch-VBridgerNoPreview.ps1` 和 `VBridger-NoPreview.cmd` 放进 **VBridger 安装目录**
  （与 `VBridger.exe`、`VBridger_Data\level2` 同级）。脚本只在这个目录里找游戏文件。
- Windows + PowerShell 5.1 及以上（Win10/11 自带即可）。不需要管理员权限，不联网。

**三步搞定**

1. 复制上面两个文件到 VBridger 目录。
2. 双击 `VBridger-NoPreview.cmd`，菜单是中英双语的：

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

3. 先按 `1` 自检，看输出里的偏移和记录判别是否与下表一致；确认无误再按 `2` 打补丁。

打完补丁后，VBridger 窗口里的预览区会变成空白/黑屏，**这是预期效果**。面捕输入、
Send Face Found Status、VMC 输出（默认端口 39539）、VTube Studio WebSocket 连接都不受影响。

菜单也支持直接传参，方便做快捷方式：`VBridger-NoPreview.cmd check|apply|restore`。

## 为什么需要它

VBridger 的本职工作是**接收手机传来的面捕数据并转发给别的软件**。窗口里那个 3D 角色只是
给你看的，但它始终挂着完整骨骼和几十个 BlendShape，每一帧都在渲染。你如果不看它，那就是
纯粹的浪费：GPU 占用、发热、风扇转速。

VBridger 设置里并没有关闭预览的开关（齿轮菜单里的"face"只是临时切换，且不持久，每次启动
又会自动打开）。这个补丁从场景层面把预览模型关掉，什么都不会画，而所有接收/转发脚本原样保留。

## 具体改了什么

只改 `VBridger_Data\level2` 里的**一个字节** —— 全身预览模型 `BridgitFullbody` 的
`m_IsActive` 标志（1 → 0）。另外两个预览对象在官方版本里本来就是关闭的，脚本会确认后跳过。

| 对象 | 作用 | 名字偏移 | `m_IsActive` 字节 | 原始值 | 打完补丁 |
|------|------|----------|--------------------|--------|----------|
| `BridgitFullbody` | 全身预览模型 | 110820 | **110838** | 1 | **0** |
| `Bridgit` | 头部/半身预览模型 | 108272 | 108282 | 0 | 0（不动） |
| `bridgeface3` | 备用预览网格 | 108112 | 108126 | 0 | 0（不动） |
| `iFacialMocapTestObj` | **数据链路根对象** | 108224 | 108246 | 1 | 1（**永不修改**） |

接收/转发脚本（`UnityRecieve_iFacialMocapCustom`、`UnityRecieve_FACEMOTION3D`、
`SendShape`、`GetShapeKeys`、`VMCSend`、`uOscClient`、`VTSWebSocket`）全部挂在
`iFacialMocapTestObj` 上，本补丁不会碰它。程序集里没有任何代码通过引用持有这三个预览对象，
所以把它们关掉不会引发空引用。

已在 `level2` 为 412672 字节、SHA-256 为
`2F177FB02D57D1600E4DF65A13E5E92BAE951AC9181D4186FA61B9A7396E9B52`
的版本上验证（Unity `2020.3.33f1`，Mono 后端）。

## 命令行用法

不想用菜单，也可以直接跑 PowerShell：

```powershell
# 只检查，不写入
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -DryRun

# 打补丁（先自动备份 level2.bak_<时间戳>，写完自动复验）
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1

# 回滚
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Restore
```

## 回滚

菜单 `3` 或 `-Restore` 会把最新的 `level2.bak_*` 复制回 `level2` 并复验。
也可以手动删掉 `level2`、把备份改名回来，或者用 Steam：*属性 → 已安装文件 → 验证游戏文件完整性*。

## VBridger / Steam 更新之后

更新会覆盖 `level2`，补丁自然失效 —— 再跑一次即可。如果新版本改了场景结构，脚本会**拒绝写入**
并以退出码 `1` 结束，同时打印它找到的每一条候选记录（长度前缀、`m_Layer`、`m_Tag`、
`m_IsActive`），方便判断是哪一项变了。它不会盲目写。

## 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功，或无需处理（已是关闭状态） |
| 1 | 结构校验失败 —— 版本变了，未写入任何内容 |
| 2 | 环境问题（目录不对、VBridger 正在运行、文件读不了） |
| 3 | 写入或写后复验失败 —— 已自动回滚到备份 |

## 安全设计

- **先校验再动手**：检查 Unity 版本串、`level2` 大小，以及每个目标的名字记录布局
  （4 字节长度前缀与名字长度一致、`m_Layer == 0`、`m_Tag == 0`、`m_IsActive` 只能是 0/1）。
  这样可以排除同名但不同类型的记录 —— `BridgitFullbody` 在文件里出现两次，只有一条是真
  GameObject，另一条是别的对象。
- **自动备份** `level2.bak_<yyyyMMdd-HHmmss>`，改动前就落盘。
- **只写 1 个字节**，文件长度不变，文件内部没有校验和会被破坏。
- **写后复验**，对不上自动还原备份并以 `3` 退出。
- **留痕**：`VBridgerPatchState.json` 记录路径、时间、Unity 版本、改前 SHA-256。
- 不联网、不提权、不装服务/驱动。

## 它不做什么

- 不从场景里删除预览对象，只是让它们不参与渲染。
- 不降低窗口分辨率，也与 `-batchmode -nographics` 无关（那会把整个 GUI 关掉，导致每次启动
  都要手动点一次连接）。
- 不改动追踪质量、校准或任何输出参数。
- 不包含、不修改、不再分发 VBridger 的任何文件。本仓库里没有任何游戏数据，工具只在你自己的
  机器上改那 1 个字节。

## 免责声明

非官方、社区作品，与 PiPuProductions 无任何关联，也未获其背书。使用风险自负（脚本一定会先
备份）。若作者反对，本仓库会下架。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
