# vbridger-no-preview-patch

**非官方补丁。** 让 VBridger 不再渲染窗口里的 3D 预览模型（省 GPU），而整条数据链路
（手机 iFacialMocap / FaceMotion3D 输入 -> VMC / VTube Studio / OSC 输出）完全照旧工作。

[English README](README.md)

---

## 快速开始

1. 完全退出 VBridger（托盘图标也要退）。
2. 把 `Patch-VBridgerNoPreview.ps1` 和 `VBridger-NoPreview-zh.cmd` 放到 **VBridger 安装目录**，
   也就是 `VBridger.exe` 和 `VBridger_Data\level2` 所在的那一层。脚本只在这个目录里找文件。
3. 双击 `VBridger-NoPreview-zh.cmd`：

   ```text
   ==========================================================
      VBridger 3D 预览补丁 / no-preview patch   -  unofficial
   ==========================================================

      1. 自检      - 只读，不写任何文件
      2. 打补丁    - 先备份 level2，再改 1 个字节
      3. 回滚      - 用最新备份还原 level2
      0. 退出

      英文菜单：VBridger-NoPreview.cmd
   ==========================================================

   请输入序号 [0-3]:
   ```

4. 先按 `1` 看看会改什么，再按 `2`。

打过补丁之后，VBridger 窗口里的预览区会变成空白/黑屏，这正是目的。面捕输入、Send Face Found
Status、VMC 输出（默认端口 39539）、VTube Studio 的 WebSocket 连接都不受影响。

Windows PowerShell 5.1 或更高版本即可（Win10/11 自带）。不需要管理员权限，不联网。

**用哪个启动器**

| 文件 | 菜单语言 | 编码 |
|------|----------|------|
| `VBridger-NoPreview.cmd` | 英文 | 纯 ASCII —— 任何代码页都不会乱码 |
| `VBridger-NoPreview-zh.cmd` | 中文 + 英文 | GBK（代码页 936）；其它代码页会先提示再继续 |

两者调用同一个脚本，也都支持直接传参数 `check` / `apply` / `restore`：只执行这一个动作，
跳过确认，返回脚本的退出码。

## 为什么

VBridger 的本职是接收手机传来的面捕数据、再转发给别的软件。窗口里那个 3D 角色只是给你看的，
但它带着整套骨骼和几十个表情 morph，每帧都在渲染。如果你根本不看它，那就是纯粹的 GPU 浪费。

软件界面里根本没有关闭 3D 预览的选项，只要 VBridger 在跑，它就一直在画。这个补丁把 Unity
场景里负责预览的几个对象置为不激活，于是什么都不画，而所有接收/转发数据的脚本一个都没动。

## 改了什么

只改 `VBridger_Data\level2` 里的**一个字节** —— 全身预览模型 `BridgitFullbody` 的
`m_IsActive` 标志（1 -> 0）。另外两个预览对象在当前版本里本来就是 0，脚本只做确认、不去动它。

| 对象                  | 作用                    | 名字偏移 | `m_IsActive` 偏移 | 出厂值 | 打补丁后 |
|-----------------------|-------------------------|----------|--------------------|--------|----------|
| `BridgitFullbody`      | 全身预览模型            | 110820   | **110838**         | 1      | **0**    |
| `Bridgit`              | 头部/半身预览           | 108272   | 108282             | 0      | 0（不动）|
| `bridgeface3`          | 备用预览网格            | 108112   | 108126             | 0      | 0（不动）|
| `iFacialMocapTestObj`   | **数据链路根节点**      | 108224   | 108246             | 1      | 1（**永不修改**）|

接收/转发相关的脚本（`UnityRecieve_iFacialMocapCustom`、`UnityRecieve_FACEMOTION3D`、
`SendShape`、`GetShapeKeys`、`VMCSend`、`uOscClient`、`VTSWebSocket`）全挂在
`iFacialMocapTestObj` 上，本补丁不碰它。程序集里没有任何代码引用这几个预览对象，所以关掉它们
不会在运行时引发空引用。

已验证的版本：`level2` 为 412672 字节，SHA-256
`2F177FB02D57D1600E4DF65A13E5E92BAE951AC9181D4186FA61B9A7396E9B52`
（Unity `2020.3.33f1`，Mono 后端）。

## 三个动作

| 菜单 | 命令行 | 做什么 |
|------|--------|--------|
| 1 | `-Check` | 读取 `level2`，告诉你会改几个字节。不写文件、不生成备份。 |
| 2 | *（不带参数）* | 先把 `level2` 复制成 `level2.bak_<yyyyMMdd-HHmmss>`，再清零标志，然后逐字节复验。 |
| 3 | `-Restore` | 把最新的 `level2.bak_*` 复制回去并复验。加 `-Check` 可以只预览。 |

```powershell
# 只自检
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Check

# 打补丁，然后回滚
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch-VBridgerNoPreview.ps1 -Restore
```

| 退出码 | 含义 |
|--------|------|
| 0 | 成功，或无需处理（已打过补丁 / 没有可还原的东西）|
| 1 | 文件不像这个脚本认识的 `level2`（当前安装，或者要还原的那份备份）—— 什么都没写 |
| 2 | 环境问题（脚本不在 `VBridger_Data` 旁边、文件不存在、读不了）|
| 3 | 写入或复制失败，或复验没过 —— 备份还在 |

## 安全设计

- **写之前先校验结构**：每个目标记录必须有与名字长度一致的前置 4 字节长度、`m_Layer == 0`、
  `m_Tag == 0`、`m_IsActive` ∈ {0,1}，而且整份文件里这样的记录必须**恰好一条**。这样能排掉
  同名但不是 GameObject 的记录 —— `BridgitFullbody` 在文件里出现两次，只有一次是真的。任何
  一条对不上就不写文件，退出码 `1`。
- **先备份**：`level2.bak_<时间戳>`，复制完先和原文件比对一致，再动手改。
- **只写一个字节**，文件长度不变，文件内部没有需要重算的校验和。
- **写完复验**；复验不过就把备份复制回去，退出码 `3`。
- 不联网、不需要管理员权限、不装服务驱动，也**没有状态文件** —— 目录里最新的那份备份就是全部
  记录。万一回滚拿错了文件，Steam 随时能修回来。

## 软件或 Steam 更新之后

更新会覆盖 `level2`，补丁随之失效 —— 重新按 `2` 再打一次即可。如果更新同时改动了场景布局，
脚本会拒绝写入（退出码 `1`），而不是瞎猜。

`level2.bak_*` 留一两份就够，旧的可以删（只会用到最新的那份）。回滚前脚本会先看一眼那份备份，
如果它不像 `level2` 就直接拒绝、什么都不写 —— 免得一个名字对得上的野文件把安装弄坏。不用脚本
回滚也行：把备份改名成 `level2`，或者用 Steam —— *属性 -> 已安装文件 -> 验证游戏文件完整性*。

## 这个补丁不做什么

- 它不删除场景里的预览对象，只是让它们不渲染。
- 它不动窗口，也不等于 `-batchmode -nographics`（那个会把整个界面关掉，于是每次启动都要手动点
  连接）。
- 它不改面捕质量、校准，也不改任何输出参数。
- 它不分发、也不修改 VBridger 的原始文件。仓库里不含任何 VBridger 文件 —— 工具只在你本机上
  改一个字节。

## 免责

非官方、社区维护，与 PiPuProductions 无关。风险自负；备份脚本会自动帮你做。如果作者提出异议，
本仓库会撤下。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
