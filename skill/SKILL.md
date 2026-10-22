---
name: windows-audio-repair
description: Windows 电脑"没有声音/无声/听不到声音/声音突然消失/音频设备异常"的系统化诊断与修复技能。适用于任何 Windows 10/11 电脑（OEM 机型如机械革命/联想/华硕等，Realtek/Conexant/Senary/Nahimic/Intel HDA 等音频方案）。当用户说"电脑没声音了"、"视频听不到声音"、"扬声器不工作"、"声卡驱动有问题"、"音频修复"时使用。提供分层诊断决策树、客观探针验证（IAudioClient）、设备重建、驱动 ID 匹配修复、端点注册表重置、官方驱动获取与高级安装（禁用签名）等完整流程，均带可执行脚本。
---

# Windows 音频（无声）诊断与修复

## 核心原则

1. **先验证、再修复**：不要凭感觉操作。每一步用"探针"客观验证（IAudioClient 能否创建音频流），而不是只问用户"好了吗"。
2. **分层诊断**：从基础（服务/音量）→ 引擎（探针）→ 设备（PnP/驱动ID）→ 注册表（端点）→ 系统（DISM/重启）逐层推进，每层验证后再进下一层。
3. **任何删除/修改前先备份**（reg export / 记录原值），任何高风险操作前征得用户同意（重启、卸载驱动、禁用签名）。
4. **用户亲自听到声音是最终验收**；探针只是客观中间验证。

## 诊断-修复流程（按顺序执行）

### 第 1 层：基础检查（PowerShell，免提权）

运行 `scripts/diagnose.ps1`（一键输出：服务状态、音频设备+驱动版本+硬件ID、默认播放端点、音量状态）。

人工核对关键项：
- `Audiosrv` / `AudioEndpointBuilder` 服务是否 Running（不是则启动并设为自动）
- 声卡设备 Status=OK 且 Problem=CM_PROB_NONE（有 Problem 则记下错误码）
- 默认播放设备存在、音量非 0、未静音
- 记录声卡设备 InstanceId（含 SUBSYS，如 `HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_1D05137D&REV_1001\...`）和驱动版本

若全部正常但无声 → 进第 2 层。

### 第 2 层：引擎验证（探针）

编译运行 `scripts/probe.cs`（C#，Add-Type 编译）：
```powershell
Add-Type -Path "<skill>/scripts/probe.cs" -ErrorAction SilentlyContinue
[AudioProbe.Probe]::Run()
```
- 输出 `Activate OK` → 引擎正常，问题在应用/端点选择层（查默认设备、应用音量、HDMI/耳机切换）。
- 输出 `hr=0x80004002 (E_NOINTERFACE)` → **引擎无法为端点创建音频流**：这是"所有应用无声"的确定性根因信号，继续第 3 层。

> **探针环境限制（重要）**：
> 1. 若探针报 `InvalidCastException: 指定的转换无效`——这是 CLR 对 HRESULT E_NOINTERFACE 的标准异常映射（接口方法未声明 `[PreserveSig]` 时）。本技能 probe.cs 已全部声明 `[PreserveSig]`，正常应打印 hr 值。
> 2. **Agent 代理进程/受限令牌下 WASAPI COM 接口可能假性 E_NOINTERFACE**（本案例：代理进程探针全部接口 QI 失败，但用户桌面浏览器播放完全正常）。**结论以用户实测为准**：探针 E_NOINTERFACE 后，必须请用户用浏览器/播放器实测一次声音；用户实测有声 = 引擎正常，探针结果为执行环境假象，无需继续修复。
> 3. 交叉验证可用 winmm 播放测试音（`mciSendString`，绕过 WASAPI）：返回码 0 = 传统路径正常，可帮助区分"引擎坏"与"探针环境受限"。

> 探针执行技巧：PowerShell 前台 stdout 偶发丢失，用 `run_in_background=true` + `TaskOutput(block=$true)` 读取。

### 第 3 层：设备与驱动 ID 匹配（无声常见根因层）

核心认知：**HDA 声卡由"硬件 ID（含 SUBSYS）+ 厂商驱动匹配"绑定**。系统更新（尤其 HDA 控制器驱动 `hdaudbus`）或驱动重装后，SUBSYS 可能变成 fallback 值（如 Senary 芯片的 `14F10101`），厂商驱动（只认 OEM 定制 ID 如 `1D05137D`）失配 → 设备改用微软 HDA 驱动 → 模拟扬声器端点无法激活 → 全应用无声。

检查步骤：
1. 列出所有 `HDAUDIO\FUNC_01&VEN_*&DEV_*` 设备，记录各自 SUBSYS、Status、Driver。
2. 用 `DEVPKEY_Device_HardwareIds` 和 `CompatibleIds` 核对：当前硬件 ID 是否在声卡驱动的 inf（`<驱动解压目录>\cisstrtU-base.inf` 等）的 Models 节中。
3. **若失配**（驱动不含该 SUBSYS）→ 执行设备重建（见第 4 层）；**若匹配但引擎仍 E_NOINTERFACE** → 进第 5 层。

### 第 4 层：设备重建（清除坏设备记录）

用 `scripts/rebuild_device.bat`（管理员）按需执行（用真实 InstanceId 替换）：
```bat
pnputil /remove-device "<实例ID-1>"
pnputil /remove-device "<实例ID-2>"
pnputil /scan-devices
```
- 删除**全部**相关 codec 设备记录（含 PHANTOM 幽灵实例），再扫描。
- **关键**：扫描后可能仍以 fallback ID 出现；**重启电脑**后 Windows 重新枚举硬件，常能以正确的 OEM SUBSYS 枚举（删除记录清除了坏缓存）。本案例正是"删除双记录 + 重启"后 Senary 设备以 `1D05137D` 恢复正常。
- 验证：设备 Status=OK、驱动为厂商版、扬声器端点 OK。

### 第 5 层：端点注册表重置

删除端点注册表让 AudioEndpointBuilder 从零重建（微软官方推荐）：
```powershell
# 管理员
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio" "<备份路径>.reg" /y
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render" -Recurse -Force
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture" -Recurse -Force
Restart-Service AudioEndpointBuilder, Audiosrv -Force
Stop-Process -Name audiodg -Force
```
注意：**微软 HDA 驱动可能无法激活 CX11970 类 codec 的模拟扬声器端点**——端点重建只是辅助，根本修复仍是让厂商驱动正确绑定。

### 第 6 层：驱动获取与安装

优先级：
1. **芯片厂商官方**：Senary/Conexant → `https://www.senarytech.com/DriverDownload/index.aspx`（WHQL，无验证，可直接脚本下载；本案例 CX11970 包为 `3.46.0.9_UWP2.43.0.0_DCH...zip`）。
2. **OEM 官网**：机械革命 `https://www.mechrevo.com/cn/products/wu-jie-15-x/downloads`（驱动按型号下载；下载链接需滑块验证，脚本抓 URL 后请用户浏览器下载）。
3. 微软更新目录（catalog.update.microsoft.com，需 POST 表单，成功率高但慢）。

安装方式（干净重装，避免版本号旧不覆盖）：
```bat
:: 管理员；注意：路径必须纯英文（pnputil 不识别中文路径！）
pnputil /add-driver "<英文路径>\cisstrtU-base.inf" /install /force
pnputil /add-driver "<英文路径>\cisstrtU-ext-OEM-common.inf" /install /force
pnputil /add-driver "<英文路径>\SenaryAPO\SenaryAPO.inf" /install /force
pnputil /add-driver "<英文路径>\SynaAPO\AudioService.inf" /install /force
```
> **执行通道坑**：在提权 PowerShell 脚本内调用 pnputil 输出会丢失/静默失败；**改用 .bat + 输出重定向到文件**（`pnputil ... >> log.txt 2>&1`）最可靠。中文路径会导致 pnputil 找不到文件——先把驱动复制到英文路径。

### 第 7 层：驱动 ID 失配的终极修复（改 inf + 禁用签名，需用户同意）

当厂商驱动 inf 不含设备实际 SUBSYS 时：
1. 复制官方驱动到英文路径，编辑 `cisstrtU-base.inf`：在 Models 节（`HDAUDIO\...` 组）添加一行
   `%Codec.DeviceDesc% = <DDInstall节>, HDAUDIO\FUNC_01&VEN_xx&DEV_yy&SUBSYS_zz ;fallback-ID`
2. 删除 inf `[Version]` 节的 `CatalogFile=` 行（签名校验会因内容修改而失败）。
3. 用户配合：设置→系统→恢复→高级启动→疑难解答→高级选项→启动设置→重启→按 **7**（禁用驱动程序签名强制，仅本次会话，自动恢复，可逆）。
4. 进入桌面后管理员执行 `pnputil /add-driver "<修改版inf>" /install`。
5. 验证：设备绑定厂商驱动、扬声器端点 OK、用户听到声音。
6. 正常重启后签名强制恢复，已安装驱动继续工作。

### 第 8 层：系统级

- `sfc /scannow`；`DISM /Online /Cleanup-Image /RestoreHealth`（DISM 输出用 `/LogPath` 或日志文件确认，进度条不经 stdout）。
- 系统还原点：`Get-ComputerRestorePoint`（有 10 天内的点可还原）。
- OS 升级回退窗口：`dism /Online /Get-OSUninstallWindow`。
- HDA 控制器驱动回退：设备管理器 GUI（需 DriverStore 保留旧版，inbox 驱动通常无旧版）。
- 重启电脑始终是低成本高概率手段；系统安全规则通常禁止 Agent 代触发重启，由用户手动执行。

## 常见诱因清单（诊断时优先排查）

| 诱因 | 处置 |
|---|---|
| NahimicService / 音效服务被禁用 | 设为 Automatic 并启动 |
| HDA 控制器驱动近期更新（hdaudbus） | 优先走第 4 层设备重建+重启 |
| 设备 SUBSYS fallback（OEM ID 失配） | 第 4 + 第 7 层 |
| 端点注册表损坏/孤儿端点 | 第 5 层 |
| 音量合成器个别应用静音 | 第 1 层 GUI 检查 |
| 默认播放设备被切到 HDMI/虚拟设备 | 第 1 层设置回正确设备 |

## 参考文件

- `references/senary_case.md` — 完整实战复盘（机械革命 WUJIE15XA / Senary CX11970 / Nahimic，从症状到恢复的全过程与教训）
- `references/driver_id_notes.md` — 硬件 ID / SUBSYS / 驱动匹配机制说明

## 脚本

- `scripts/diagnose.ps1` — 一键基础诊断（服务/设备/驱动/端点）
- `scripts/probe.cs` — IAudioClient 探针（客观验证引擎层）
- `scripts/rebuild_device.bat` — 设备重建模板（需替换实例 ID）
- `scripts/reset_mmdevices.ps1` — 端点注册表重置（管理员）
