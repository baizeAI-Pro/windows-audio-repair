# 实战复盘：机械革命 WUJIE15XA 无声故障完整修复过程

> 本文是 windows-audio-repair 技能的"出生案例"，记录了从症状到修复的全过程、关键判断与踩坑教训。遇到类似环境（机械革命/同方系机型 + Senary/Conexant CX11970 声卡 + Nahimic 音效）时优先参考本案例。

## 一、环境

- 机型：MECHREVO（机械革命）无界15X / WUJIE15XA（Uniwill GX5HRXG-GX4HRXL，AMD Hawk Point）
- 系统：Windows 11 25H2（Build 26200）
- 音频方案：Senary Audio（Conexant CX11970 系，`VEN_14F1&DEV_1F87`）+ Nahimic APO 4 + AMD HDMI 音频
- 症状：打开视频听不到声音，所有应用均无声（系统音效、音乐、视频全部无声）

## 二、完整诊断过程

### 2.1 基础层（全部正常）

- Audiosrv / AudioEndpointBuilder：Running
- 声卡设备 Senary Audio：Status=OK，ConfigManagerErrorCode=0
- 默认播放设备"扬声器 (Senary Audio)"：音量 100%、未静音
- audiodg 进程存在；所有 MMDDevices 端点枚举正常
- 驱动均有 WHQL 签名（Senary 3.48.30.15 / SenaryAPO 1.18.0.2 / A-Volute Nh4 4.11.7.0）

→ 表面一切正常，但无声 → 必须做引擎层验证。

### 2.2 引擎层（定位到根因信号）

用 C# 探针（WASAPI）调用 `IAudioClient::Activate` 创建输出流：

```
Activate IAudioClient 失败 hr=0x80004002 pClient=0  (E_NOINTERFACE)
```

**关键认知**：E_NOINTERFACE = 音频引擎无法为播放端点创建渲染流实例。端点接口（音量/静音）由端点自身提供所以正常，但引擎实例化失败 → 全应用无声。**这就是确定性根因信号**，不必再怀疑静音/音量。

### 2.3 疑点排查

- 事件日志：2026-10-14 SenaryAudioApp.exe 重启失败（"Application SID does not match Conductor SID"）
- NahimicService 被 **Disabled**（→ 已恢复 Automatic + Running）
- 2026-10-10 HDA 控制器驱动（hdaudbus）被更新为 10.0.26100.9711 ← **重大嫌疑**
- audiodg 从未加载任何 Senary/Nahimic APO 模块（组件 DLL/CLSID/设备实例齐全但未进入引擎）

### 2.4 试错的修复清单（前 8 项全部无效，每项后用探针复测仍是 E_NOINTERFACE）

1. 重启音频服务（Audiosrv + AudioEndpointBuilder）
2. 恢复 NahimicService 为自动并启动
3. 重启 audiodg 进程
4. 禁用再启用 Senary 设备
5. pnputil /remove-device 卸载设备再重扫
6. 移除扬声器端点的 6 个 Nahimic APO 注册键（先 reg export 备份）
7. SFC /scannow（无损坏）
8. 服务级完全重置 + 播放触发
9. 强制重装 oem17/oem21/oem45.inf（驱动包）
10. 用户手动重启电脑 → **仍无声**

### 2.5 根因确认（设备 ID 失配）

重启后复测发现**设备视图分裂**：
- `HDAUDIO\...&SUBSYS_1D05137D`（Senary Audio）→ PHANTOM 幽灵
- `HDAUDIO\...&SUBSYS_14F10101`（High Definition Audio 设备）→ 在线，但用的是**微软 HDA 驱动**

查询设备硬件 ID 列表：只有 `SUBSYS_14F10101` 和 `SUBSYS_14F10101&REV_1001`，**不含 Senary 驱动唯一匹配的 1D05137D**。

**根因链条**：
1. 2026-10-10 hdaudbus（HDA 总线驱动）更新到 10.0.26100.9711
2. 更新后 codec 的 SUBSYS 解析为 fallback 值 `14F10101`（厂商定制 `1D05137D` 不再被识别）
3. Senary 驱动 inf 只匹配 `1D05137D` → 无法绑定 → 设备落到微软 HDA 驱动
4. 微软 HDA 驱动无法激活 CX11970 的模拟扬声器端点（SPDIF 能激活但扬声器不能）→ 全应用无声
5. 旧 Senary 端点成为孤儿（Unknown），引擎对任何渲染端点均 E_NOINTERFACE

## 三、最终修复（关键动作组合）

1. **驱动入库（官方包）**：从机械革命官网下载无界15X 声卡驱动 `6.Audio.zip`（内含 `3.48.16.5_UWP2.45.4.0_DCH_W10-W11_WHQL_Common_20240304`，inf 含 `HdAud2021.GX4HRXL` 机型节）。
2. **设备重建**：`pnputil /remove-device` 删除**两条**设备记录（1D05137D 幽灵 + 14F10101 在线）→ `pnputil /scan-devices`。
3. **端点重置**：删除 `MMDevices\Audio\Render|Capture` 注册表 → 重启 AudioEndpointBuilder/Audiosrv → 端点从零重建。
4. **用户重启电脑**（走高级启动流程，多次重启）。
5. **结果**：重启后 Windows 重新枚举硬件，Senary 设备以 **`SUBSYS_1D05137D`** 恢复在线（驱动 3.48.30.15，Status OK），扬声器 (Senary Audio) 端点重建且成为默认播放设备 → **声音恢复**。

> 判断：删除坏设备记录清除了注册表/枚举缓存，重启后 hdaudbus 正确读取 codec SUBSYS，Senary 驱动重新匹配。若删除后扫描/重启仍未恢复 1D05137D，则需走 SKILL.md 第 7 层（改 inf + 禁用签名强制安装）。

## 四、可复用的踩坑教训

1. **探针是唯一的客观验证**：不要靠"重启服务后问用户"循环，每次修复后用探针复测。
2. **提权脚本内调用 pnputil 会静默失败/丢输出**：改用 `.bat` 文件 + `>> log.txt 2>&1` 重定向，由 `cmd /c` 以管理员运行最可靠。
3. **pnputil 不识别中文路径**：驱动文件一律先复制到纯英文路径（如 `D:\SystemCache\Temp\...`）。
4. **官网驱动下载常被滑块/验证拦截**：脚本抓 URL 后请用户浏览器手动下载；或走芯片厂商站（深蕾 senarytech.com，无验证，WHQL 可直链）。
5. **版本号比较陷阱**：官网包内驱动版本可能低于当前已装版本（页面"更新日期"≠驱动日期），`pnputil /add-driver` 不会覆盖低版本——需先删旧包或用 `/force`，或依赖"设备重建后自动重新匹配"。
6. **PHANTOM 设备无法 Enable**：幽灵设备记录只能 `pnputil /remove-device` 删除后靠重新枚举恢复。
7. **SetDefaultEndpoint（IPolicyConfig）只是切换默认设备**，无法修复引擎级 E_NOINTERFACE。
8. **系统级兜底**：SFC/DISM/还原点/回退窗口逐一确认过；inbox 驱动（hdaudbus）通常无旧版可回退。
9. **GitHub 同款参考**：`sharkcpt/Mechrevo-Tongfang-Andio-Senary-Nahimic-Driver-FIX-Sampling-rate`（同方系 Senary 驱动修复包，需禁用签名安装，README 明确说明）。

## 五、备份与资产位置（本案例遗留，供恢复用）

- Nahimic APO 端点注册备份：`D:\SystemCache\Temp\render_backup_*.reg`
- MMDevices 全量备份：`D:\SystemCache\Temp\mm_audio_full_backup_*.reg`
- 官网驱动包：`D:\音频处理\6.Audio.zip`
- 修改版驱动：`D:\SystemCache\Temp\senary1615_mod\cisstrtU-base.inf`（含 14F10101 条目，无 CatalogFile）
