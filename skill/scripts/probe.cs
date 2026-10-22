// 音频引擎探针：验证 Windows 音频引擎能否为默认播放端点创建音频流
// 编译运行（PowerShell）：
//   Add-Type -Path "probe.cs" -ErrorAction SilentlyContinue
//   [AudioProbe.Probe]::Run()
// 结果解读：
//   "Activate OK"                   -> 引擎正常，问题在应用/默认设备/音量层
//   "hr=0x80004002 (E_NOINTERFACE)" -> 引擎无法创建音频流 = "全应用无声"的确定性根因信号
// 注意：接口方法均声明 [PreserveSig]，直接返回 HRESULT 数值；
//       若不声明，CLR 会把 E_NOINTERFACE 转成 InvalidCastException("指定的转换无效")。
using System;
using System.Runtime.InteropServices;

namespace AudioProbe {
    public static class Probe {
        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDevEnum { }
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator {
            [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
            [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
            [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
            [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
        }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice {
            [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr par, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
            [PreserveSig] int OpenPropertyStore(int access, out IntPtr store);
            [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
            [PreserveSig] int GetState(out int state);
        }
        [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568DF703B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioClient { }

        public static void Run() {
            try {
                var e = (IMMDeviceEnumerator)new MMDevEnum();
                IMMDevice def;
                int hr = e.GetDefaultAudioEndpoint(0, 1, out def);
                if (hr != 0) {
                    Console.WriteLine("GetDefaultAudioEndpoint 失败 hr=0x" + hr.ToString("X8") + " (无默认播放设备)");
                    Console.WriteLine("=== DONE ===");
                    return;
                }
                string id; def.GetId(out id);
                int st; def.GetState(out st);
                Console.WriteLine("默认播放端点: " + id + " state=" + st);
                Guid iid = typeof(IAudioClient).GUID;
                object iface = null;
                int hr2 = def.Activate(ref iid, 0x1 | 0x4, IntPtr.Zero, out iface);
                Console.WriteLine("Activate IAudioClient: hr=0x" + hr2.ToString("X8"));
                if (hr2 == 0) {
                    Console.WriteLine("Activate OK");
                } else if (hr2 == unchecked((int)0x80004002)) {
                    Console.WriteLine("E_NOINTERFACE - 引擎无法为端点创建音频流(全应用无声根因信号)");
                } else {
                    Console.WriteLine("其他错误");
                }
                if (iface != null) Marshal.ReleaseComObject(iface);
            } catch (Exception ex) {
                Console.WriteLine("EX: " + ex.GetType().Name + ": " + ex.Message);
            }
            Console.WriteLine("=== DONE ===");
        }
    }
}
