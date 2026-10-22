# 硬件 ID / SUBSYS / 驱动匹配机制说明

## 1. HDA 声卡设备如何被枚举与绑定

Windows HDA 音频设备由 `hdaudbus`（HDA 总线驱动）枚举，生成设备实例 ID：

```
HDAUDIO\FUNC_01&VEN_<厂商ID>&DEV_<设备ID>&SUBSYS_<子系统ID>&REV_<版本>\
```

- VEN/DEV：codec 芯片厂商与型号（如 `VEN_14F1&DEV_1F87` = Senary/Conexant CX11970 系列）
- **SUBSYS**：子系统 ID，通常来自 codec 引脚/固件或主板 BIOS 设定，**是 OEM 定制与通用 fallback 的关键**
- 厂商驱动 inf 的 Models 节列出它支持的精确 ID（含 SUBSYS）；匹配成功设备才绑定厂商驱动

## 2. SUBSYS fallback 场景（无声高发原因）

- 常见 fallback：`SUBSYS_14F10101`（VEN 厂商 ID + 0101 默认值）等"通用值"
- OEM 定制值：如机械革命无界15X = `SUBSYS_1D05137D`
- **触发 fallback 的诱因**：HDA 总线驱动（hdaudbus）更新、BIOS/EC 更新改变 SDO 配置、设备记录损坏、系统大版本升级（如 24H2→25H2）
- **后果**：厂商驱动（只认 OEM SUBSYS）失配 → 设备落到微软 HDA 驱动 → 部分 codec 的**模拟扬声器端点无法激活**（CX11970 实测：SPDIF 可激活、扬声器 E_NOINTERFACE）→ 全应用无声

## 3. 检查命令速查

```powershell
# 列出所有 codec 设备（含 SUBSYS、状态、驱动版本）
Get-PnpDevice | Where-Object { $_.InstanceId -match 'HDAUDIO\\FUNC_01' } | ForEach-Object {
    $v = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion'
    $n = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DeviceDesc'
    [PSCustomObject]@{ Id=$_.InstanceId; Status=$_.Status; Problem=$_.Problem; Ver=$v.Data; Desc=$n.Data }
} | Format-List

# 查看设备硬件 ID 与兼容 ID
$d = Get-PnpDevice | Where-Object { $_.InstanceId -like '*SUBSYS_14F10101*' }
(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds').Data
(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_CompatibleIds').Data

# 驱动库里的厂商驱动包及版本
pnputil /enum-drivers | Select-String -Pattern 'cisstrt|Senary|A-Volute|Realtek' -Context 1,3
```

## 4. inf 修改要点（第 7 层终极修复用）

- 位置：`cisstrtU-base.inf` 的 Models 节（`[HdAud2021...Models]` 或含 `%Codec.DeviceDesc% = <DDInstall>, <硬件ID>` 的行）
- 在 `HDAUDIO\...` 组追加一行：
  `%Codec.DeviceDesc% = <DDInstall节>, HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_14F10101 ;fallback`
- 删除 `[Version]` 节的 `CatalogFile=` 行（内容变更后签名校验必失败，须配合"禁用驱动签名强制"会话安装）
- 修改后安装：高级启动 → 疑难解答 → 高级选项 → 启动设置 → 重启 → 按 7（仅本次会话生效，自动恢复）

## 5. 驱动版本号陷阱

- `pnputil /add-driver inf /install` 只在版本**更高**时覆盖设备驱动；低版本默认跳过
- OEM 包的"页面更新日期"≠驱动实际版本（如官网显示 2026/02/10，包内驱动 2024/03）——**以 inf 的 DriverVer 为准**
- 强制覆盖：`pnputil /add-driver inf /install /force`，或先 `pnputil /delete-driver <oemXX.inf> /uninstall /force` 删旧包再装
