# windows-audio-repair · Windows 无声故障诊断与修复

> 一次真实的 Windows 全应用无声故障完整复盘：从现象定位到根因、从根因到修复，并沉淀为可交给任意 AI Agent 直接执行的诊断-修复技能。

## 问题背景

2026-10-21，一台机械革命无界15X（WUJIE15XA / Uniwill GX5HRXG-GX4HRXL，AMD Hawk Point，Windows 11 25H2 Build 26200）突然出现**打开视频听不到声音，且所有应用（系统音效、音乐、视频）全部无声**。

基础检查全部正常：音频服务 Running、声卡设备无错误、音量 100% 未静音、驱动均有 WHQL 签名。问题出在更深一层。

## 根因（一句话版）

2026-10-10 Windows Update 更新了 HDA 总线驱动 `hdaudbus`（10.0.26100.9711）后，codec 的 SUBSYS 被解析为 fallback 值 `14F10101`，而厂商 Senary 驱动（Conexant CX11970 系）的 inf 只认 OEM 定制值 `1D05137D` → 驱动失配 → 设备落到微软 HDA 驱动 → 微软 HDA 驱动无法激活模拟扬声器端点（SPDIF 可、扬声器不可）→ 全应用无声。

**诊断信号**：WASAPI 引擎探针稳定返回 `E_NOINTERFACE (0x80004002)`，即音频引擎无法为渲染端点创建音频流——这是"全应用无声"的确定性根因信号。

## 修复方案（有效组合）

| 步骤 | 操作 |
|---|---|
| 1 | 从厂商官网下载匹配机型的官方声卡驱动包（Senary 3.48.16.5 官方包，含本机机型节） |
| 2 | 驱动复制到纯英文路径，`pnputil /add-driver` 入库 |
| 3 | `pnputil /remove-device` 删除两条设备记录（幽灵 1D05137D + 在线 14F10101） |
| 4 | `pnputil /scan-devices` 重新扫描 |
| 5 | 删除 `MMDevices\Audio\Render\|Capture` 注册表（先备份） |
| 6 | 重启 AudioEndpointBuilder / Audiosrv |
| 7 | **手动重启电脑** → codec 以 `1D05137D` 正确枚举 → Senary 驱动重新绑定，扬声器端点重建，声音恢复 |

> 备选方案（本案例未用）：修改驱动 inf 的 Models 节加入 fallback SUBSYS + 禁用驱动签名强制安装。参考同款 GitHub 项目 `sharkcpt/Mechrevo-Tongfang-Andio-Senary-Nahimic-Driver-FIX-Sampling-rate`。

## 经验文档

- [docs/Windows电脑无声问题诊断与修复-经验文档.md](docs/Windows电脑无声问题诊断与修复-经验文档.md) —— 完整复盘：时间线、分层诊断路径、根因链条、修复表、12 条踩坑教训、关键 ID 附录。

## 可复用技能（交给任意 AI Agent）

目录 [`skill/`](skill/) 是一个完整的 Agent Skill 包，把 8 层诊断-修复决策树封装为可直接执行的流程：

```
skill/
├── SKILL.md                      # 8 层诊断-修复决策树 + 诱因清单
├── scripts/
│   ├── diagnose.ps1              # 一键基础诊断（服务/设备/驱动/端点/音量）
│   ├── probe.cs                  # WASAPI 引擎探针（PreserveSig 版，返回 HRESULT）
│   ├── rebuild_device.bat        # 设备重建模板（替换实例 ID 后管理员运行）
│   └── reset_mmdevices.ps1       # 端点注册表重置（管理员，先备份）
└── references/
    ├── senary_case.md            # 本案例完整复盘（全部硬件 ID 与时间线）
    └── driver_id_notes.md        # 硬件 ID / SUBSYS / 驱动匹配机制
```

### 使用方法

1. 将 `skill/` 目录整体复制到任意本地 Agent 的技能目录（如 `workspace/.user_skills/windows-audio-repair/`）
2. 对 Agent 说："电脑没声音了，用 windows-audio-repair 技能诊断修复"
3. Agent 读取 SKILL.md 按 8 层流程执行

### 也可以手动跑

- `diagnose.ps1`（管理员）：一键输出服务/设备/驱动/端点/音量状态
- `probe.cs`：编译为探针，客观验证 WASAPI 引擎能否创建音频流
- `reset_mmdevices.ps1`（管理员）：删除端点注册表并重建（微软官方推荐修复）
- `rebuild_device.bat`（管理员）：删除坏设备记录后重新扫描枚举

## 关键技术教训（详见经验文档）

1. **waveOut（winmm/mci）与 WASAPI 是两条路径**：旧 API 有声 ≠ 现代应用正常。
2. **探针报 E_NOINTERFACE 后必须请用户实测**：Agent 代理进程（受限令牌）下 WASAPI COM 接口可能假性 E_NOINTERFACE。
3. **CLR 的 `InvalidCastException: 指定的转换无效` 就是 HRESULT E_NOINTERFACE 的异常映射**；接口方法声明 `[PreserveSig]` 可直接拿到 HRESULT 数值。
4. **pnputil 在提权 PowerShell 内会静默失败** → 改用 `.bat` + 输出重定向最可靠；且不识别中文路径。
5. **删除任何东西前先备份**（reg export / 记录原值）。
6. **PHANTOM 幽灵设备无法 Enable** → 只能 `pnputil /remove-device` 删除后靠重新枚举恢复。

## 适用范围

- 机械革命/同方国际（Tongfang）机型 + Senary/Conexant 声卡（VEN_14F1）优先受益
- 所有"设备正常但全应用无声"的 Windows 电脑均可按 8 层流程排查
- 已实测：Windows 11 25H2 / Senary Audio（CX11970 系，VEN_14F1&DEV_1F87）

## 许可

MIT License。分享给需要的人，但请先理解每一步在做什么再执行——涉及驱动卸载、注册表删除与重启等系统级操作，**执行前务必先备份**。

---

*案例时间：2026-10-21 至 2026-10-22。文档与技能由实战验证（用户浏览器 WASAPI 实测有声确认修复成功）。*
