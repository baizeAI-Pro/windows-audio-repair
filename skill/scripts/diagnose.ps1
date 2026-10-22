# Windows 音频一键诊断脚本（免提权）
# 输出：音频服务状态 / 音频设备与驱动版本 / 硬件ID / 默认播放端点 / 音量状态
# 用法：powershell -ExecutionPolicy Bypass -File diagnose.ps1
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

"===== 1. 音频服务状态 ====="
Get-Service Audiosrv, AudioEndpointBuilder | Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-String -Width 120

"===== 2. 音频设备与驱动 ====="
Get-PnpDevice | Where-Object { $_.InstanceId -match 'HDAUDIO\\FUNC_01|VEN_14F1|Realtek|Intel.*Audio' } | ForEach-Object {
    $ver = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion'
    $name = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DeviceDesc'
    [PSCustomObject]@{
        InstanceId = $_.InstanceId
        Status     = $_.Status
        Problem    = $_.Problem
        Driver     = $ver.Data
        Desc       = $name.Data
    }
} | Format-List | Out-String -Width 250

"===== 3. 音频端点 ====="
Get-PnpDevice | Where-Object { $_.InstanceId -match 'MMDEVAPI' } | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 250

"===== 4. 默认播放设备音量/静音状态 ====="
Add-Type @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDevEnum { }
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator2 {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice2 device);
    int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice2 device);
    int RegisterEndpointNotificationCallback(IntPtr client);
    int UnregisterEndpointNotificationCallback(IntPtr client);
}
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice2 {
    int Activate(ref Guid iid, int clsCtx, IntPtr par, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    int OpenPropertyStore(int access, out IntPtr store);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    int GetState(out int state);
}
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr notify);
    int UnregisterControlChangeNotify(IntPtr notify);
    int GetChannelCount(out uint count);
    int SetMasterVolumeLevel(float level, ref Guid ctx);
    int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
    int GetMasterVolumeLevel(out float level);
    int GetMasterVolumeLevelScalar(out float level);
    int SetChannelVolumeLevel(uint ch, float level, ref Guid ctx);
    int SetChannelVolumeLevelScalar(uint ch, float level, ref Guid ctx);
    int GetChannelVolumeLevel(uint ch, out float level);
    int GetChannelVolumeLevelScalar(uint ch, out float level);
    int SetMute(bool mute, ref Guid ctx);
    int GetMute(out bool mute);
}
'@
$e = [Activator]::CreateInstance([Type]::GetTypeFromCLSID('BCDE0395-E52F-467C-8E3D-C4579291692E'))
$dev = $e.GetDefaultAudioEndpoint(0, 1)
$id = $dev.GetId()
$st = $dev.GetState()
"默认播放端点: $id  state=$st"
$iid = [Guid]'5CDF2C82-841E-4546-9722-0CF74078229A'
$iface = $dev.Activate($iid, 3, [IntPtr]::Zero)
$vol = [System.Runtime.InteropServices.Marshal]::GetObjectForIUnknown($iface)
$lv = $null; $vol.GetMasterVolumeLevelScalar([ref]$lv)
$mute = $null; $vol.GetMute([ref]$mute)
"音量: $([math]::Round($lv*100))%  静音: $mute"

"===== 5. 声音方案驱动包（DriverStore）====="
pnputil /enum-drivers | Select-String -Pattern 'cisstrt|Realtek|RTKVHD|intcdaud|Nahimic|A-Volute|a-volute' -Context 1,3 | Out-String -Width 200

"===== 诊断完成。若以上全正常但无声，运行 probe.cs 验证引擎层 ====="
