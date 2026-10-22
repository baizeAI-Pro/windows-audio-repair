# 端点注册表重置（微软官方推荐修复：删除端点 -> AudioEndpointBuilder 从零重建）
# 需管理员运行。先备份，再删除 Render/Capture 端点键，重启音频服务。
# 用法：powershell -ExecutionPolicy Bypass -File reset_mmdevices.ps1
$ErrorActionPreference = 'SilentlyContinue'

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $env:TEMP ("mm_audio_full_backup_" + $ts + ".reg")
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio" $backup /y
Write-Output "备份: $backup"

Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render" -Recurse -Force
Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture" -Recurse -Force
Write-Output "端点键已删除"

Restart-Service -Name AudioEndpointBuilder, Audiosrv -Force
Stop-Process -Name audiodg -Force
Start-Sleep -Seconds 10

$cnt = (Get-ChildItem -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render").Count
Write-Output "重建后 Render 端点数量: $cnt"
Write-Output "完成。若仍无声，检查设备是否以厂商驱动绑定(见 SKILL.md 第3/4层)。"
