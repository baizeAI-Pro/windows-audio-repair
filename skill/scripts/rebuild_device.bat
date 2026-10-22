@echo off
REM ============================================================
REM 音频设备重建模板（需管理员运行）
REM 用法：把下面两个 <实例ID> 替换为 diagnose.ps1 输出的真实
REM       HDAUDIO 设备 InstanceId（含 PHANTOM 实例一并删除），
REM       再以管理员运行本文件。
REM 删除记录 -> 重新扫描 -> 重启电脑后 Windows 重新正确枚举声卡。
REM ============================================================
set LOG=D:\SystemCache\Temp\rebuild_audio_log.txt
echo === 设备重建 %date% %time% === > %LOG%

echo 删除设备记录1... >> %LOG% 2>&1
pnputil /remove-device "HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_1D05137D&REV_1001\5&24608760&0&0001" >> %LOG% 2>&1
echo --- exit %errorlevel% --- >> %LOG% 2>&1

echo 删除设备记录2(fallback)... >> %LOG% 2>&1
pnputil /remove-device "HDAUDIO\FUNC_01&VEN_14F1&DEV_1F87&SUBSYS_14F10101&REV_1001\5&24608760&0&0001" >> %LOG% 2>&1
echo --- exit %errorlevel% --- >> %LOG% 2>&1

echo 重新扫描硬件... >> %LOG% 2>&1
pnputil /scan-devices >> %LOG% 2>&1
echo --- exit %errorlevel% --- >> %LOG% 2>&1

echo === 完成。请重启电脑让 Windows 重新枚举声卡 === >> %LOG% 2>&1
type %LOG%
