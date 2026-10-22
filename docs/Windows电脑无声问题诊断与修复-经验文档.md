# Windows 电脑无声故障：诊断与修复经验文档（实战复盘）

> **文档性质**：本文档沉淀"机械革命无界15X 全应用无声"故障的完整诊断、定位、修复过程与可复用经验。下次遇到类似问题，可直接按本文档第 5/6 节步骤操作，或交给任意本地 Agent 使用第 7 节的可复用技能 `windows-audio-repair`。

---

## 1. 故障现象与时间线

| 时间 | 事件 |
|---|---|
| 2026-10-10 | Windows Update 更新 HDA 控制器驱动（hdaudbus → 10.0.26100.9711）|
| 2026-10-14 | 事件日志：SenaryAudioApp.exe 重启失败（Application SID 不匹配）|
| 2026-10-21 | 用户打开视频发现**所有应用无声**（系统音效、音乐、视频全部无声音）|
| 2026-10-21 | 完成 10 项修复尝试均无效；确认根因（设备 SUBSYS 失配）|
| 2026-10-21 | 驱动入库 + 删除设备记录 + 端点重置 + 用户手动重启 → **设备恢复 Senary 官方驱动绑定** |
| 2026-10-22 | 深度验证：winmm 播放正常、浏览器（WASAPI）有声，**用户确认声音完全恢复** |

## 2. 机器环境

- 机型：机械革命 无界15X / WUJIE15XA（Uniwill GX5HRXG-GX4HRXL，AMD Hawk Point）
- 系统：Windows 11 25H2（Build 26200）
- 音频方案：**Senary Audio（Conexant CX11970 系，VEN_14F1&DEV_1F87）** + Nahimic APO 4 + AMD HDMI
- 症状特征：设备管理器显示正常、音量 100%、未静音，但所有应用无声

## 3. 分层诊断过程（定位路径）

### 第 1 层：基础检查（全部正常，排除了常规原因）
- Audiosrv / AudioEndpointBuilder 服务：Running
- Senary 声卡设备：Status=OK，无错误码
- 默认播放设备"扬声器 (Senary Audio)"：音量 100%、未静音
- 驱动均有 WHQL 签名（Senary 3.48.30.15 / SenaryAPO 1.18.0.2 / A-Volute Nh4 4.11.7.0）

### 第 2 层：引擎层验证（关键一步）
用 C# WASAPI 探针（IAudioClient::Activate）客观验证：
```
Activate IAudioClient 失败 hr=0x80004002 (E_NOINTERFACE)
```
**判定**：音频引擎无法为播放端点创建渲染流 = "全应用无声"的确定性根因信号，而非音量/静音问题。

### 第 3 层：设备与驱动 ID 匹配（找到根因）
重启后复测，发现设备视图"分裂"：
- `HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_1D05137D`（Senary Audio）→ **PHANTOM 幽灵**
- `HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_14F10101`（High Definition Audio 设备）→ 在线，但绑**微软 HDA 驱动**

核对 Senary 驱动 inf 的 Models 节：**只认 `SUBSYS_1D05137D`**，不含 `14F10101` → 驱动失配。

## 4. 根因链条

```
2026-10-10 hdaudbus（HDA 总线驱动）更新到 10.0.26100.9711
  → codec SUBSYS 被解析为 fallback 值 14F10101（OEM 定制值 1D05137D 不再被识别）
  → Senary 驱动（inf 只匹配 1D05137D）无法绑定
  → 设备落到微软 HDA 驱动
  → 微软 HDA 驱动无法激活 CX11970 的模拟扬声器端点（SPDIF 可、扬声器不可）
  → 全应用无声（引擎对渲染端点 E_NOINTERFACE）
```

## 5. 修复过程（有效动作组合 = 最终方案）

| 步骤 | 操作 | 说明 |
|---|---|---|
| 1 | 从机械革命官网下载无界15X 声卡驱动 `6.Audio.zip`（官方包 3.48.16.5，含本机 GX4HRXL 机型节）| 下载需滑块验证，脚本抓 URL 后**由用户浏览器手动下载** |
| 2 | 驱动复制到**纯英文路径**，`pnputil /add-driver` 入库 oem37/61/62/63 | 中文路径会导致 pnputil 失败 |
| 3 | `pnputil /remove-device` 删除**两条**设备记录（1D05137D 幽灵 + 14F10101 在线）| 清除坏设备记录 |
| 4 | `pnputil /scan-devices` 重新扫描 | |
| 5 | 删除 `MMDevices\Audio\Render\|Capture` 注册表（先备份）| 端点从零重建 |
| 6 | 重启 AudioEndpointBuilder / Audiosrv | |
| 7 | **用户手动重启电脑** | 重启后 Windows 以 `1D05137D` 正确枚举 codec → Senary 驱动重新绑定 |

**修复生效标志**：
- Senary 设备恢复 `HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_1D05137D`，Status=OK，驱动 3.48.30.15
- 扬声器 (Senary Audio) 端点重建，状态 OK，且为默认播放设备
- 用户浏览器（WASAPI 路径）实测有声 ✅

> 备选方案（本案例最终未用）：修改版 inf（给 cisstrtU-base.inf 的 Models 节加 `SUBSYS_14F10101` 行、删除 `CatalogFile=`）+ 高级启动"禁用驱动签名强制"安装——当"删除设备记录+重启"仍无法恢复 OEM SUBSYS 时使用。参考 GitHub 项目 `sharkcpt/Mechrevo-Tongfang-Andio-Senary-Nahimic-Driver-FIX-Sampling-rate`。

## 6. 关键经验与踩坑教训

1. **探针是唯一客观验证**：不要靠"重启服务后问用户"循环；每次修复后用探针复测，且以用户实测为最终权威。
2. **探针环境限制**：Agent 代理进程（受限令牌）下 WASAPI COM 接口可能假性 E_NOINTERFACE——本案例探针全接口 QI 失败，但用户桌面浏览器播放完全正常。**探针报 E_NOINTERFACE 后必须请用户实测**；用户有声 = 引擎正常。
3. **`InvalidCastException: 指定的转换无效` = HRESULT E_NOINTERFACE 的 CLR 异常映射**；接口方法声明 `[PreserveSig]` 可直接拿到 HRESULT 数值。
4. **waveOut（winmm/mci）与 WASAPI 是两条路径**：waveOut 有声 ≠ WASAPI 正常（waveOut 不构建 APO 链）。反之亦然——验证现代应用必须走 WASAPI。
5. **pnputil 在提权 PowerShell 内会静默失败/丢输出** → 改用 `.bat` + `>> log 2>&1` 文件重定向最可靠。
6. **pnputil 不识别中文路径** → 驱动先复制到英文路径（如 `D:\SystemCache\Temp\...`）。
7. **版本号陷阱**：官网驱动包内版本可能低于已装版本，`pnputil /add-driver` 默认不覆盖低版本（需 `/force` 或依赖设备重建后自动匹配）；页面"更新日期"≠驱动实际版本，以 inf 的 DriverVer 为准。
8. **PHANTOM 幽灵设备无法 Enable** → 只能 `pnputil /remove-device` 删除后靠重新枚举恢复。
9. **SetDefaultEndpoint（IPolicyConfig）只切换默认设备**，无法修复引擎级故障。
10. **服务重置/audiodg 重启需管理员权限**；audiodg 是 SYSTEM 进程，普通权限 Stop-Process 无效（表面"已停止"实为失败）。
11. **NahimicService 被 Disabled** 是无声高发诱因之一（本次已恢复 Automatic+Running）。
12. **任何删除前先备份**（reg export / 记录原值），高风险操作（重启、卸载驱动、禁用签名）先征得用户同意。

## 7. 可复用技能（交给任意本地 Agent 即可复现修复）

技能名称：**`windows-audio-repair`**
位置：`C:\Users\14538\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills\windows-audio-repair\`

```
windows-audio-repair/
├── SKILL.md                      # 8 层诊断-修复流程 + 诱因清单
├── scripts/
│   ├── diagnose.ps1              # 一键基础诊断（服务/设备/驱动/端点/音量）
│   ├── probe.cs                  # WASAPI 引擎探针（PreserveSig 版）
│   ├── rebuild_device.bat        # 设备重建模板（替换实例 ID 后管理员运行）
│   └── reset_mmdevices.ps1       # 端点注册表重置（管理员）
└── references/
    ├── senary_case.md            # 本案例完整复盘（含全部 ID 与时间线）
    └── driver_id_notes.md        # 硬件 ID / SUBSYS / 驱动匹配机制
```

**使用方式**：把该文件夹交给任意本地 Agent（放入其技能目录），当用户说"电脑没声音/视频听不到声音"时，Agent 读取 SKILL.md 按 8 层流程执行即可。已通过 `quick_validate.py` 校验（Skill is valid!）。

## 8. 附录：关键 ID 与资产

- 修复后健康设备：`HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_1D05137D&REV_1001\5&24608760&0&0001`（Senary Audio，oem17.inf / 3.48.30.15）
- 幽灵设备：`HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_14F10101&REV_1001\...`（已删除记录，勿再手动创建）
- 当前默认播放端点：`SWD\MMDEVAPI\{0.0.0.00000000}.{3648d740-bdcd-4e43-9f77-2fb3a45e9a56}`（扬声器 Senary Audio）
- 官网驱动包：`D:\音频处理\6.Audio.zip`（用户已下载）；解压产物在 `D:\音频处理\6.Audio\...`
- 注册表备份：`%TEMP%\mm_audio_full_backup_*.reg`
- 修改版驱动（备用）：`D:\SystemCache\Temp\senary1615_mod\cisstrtU-base.inf`
- 参考链接：
  - 机械革命无界15X 驱动页：`https://www.mechrevo.com/cn/products/wu-jie-15-x/downloads`
  - 深蕾科技（Senary 官方，WHQL 可直链）：`https://www.senarytech.com/DriverDownload/index.aspx`
  - GitHub 同款修复项目：`https://github.com/sharkcpt/Mechrevo-Tongfang-Andio-Senary-Nahimic-Driver-FIX-Sampling-rate`

---

*文档生成：2026-10-22。验证方式：设备 Status=OK、端点 OK 且默认、winmm 播放成功、用户浏览器实测有声。*
