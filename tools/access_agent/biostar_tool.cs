// Zouti pou tèminal Suprema sou rezo a (BioEntry W2 elatriye) atravè
// BioStar Device SDK (BS_SDK_V2.dll, Cdecl). Chak apèl se yon pwosesis:
//   biostar_tool.exe <dllDir> search              -> count\tN, apre device\tid\ttype\tip\tport
//   biostar_tool.exe <dllDir> ping <ip> [port]    -> ok\t<id>\t<type>\t<ip> | err\t<code>\t<msg>
//   biostar_tool.exe <dllDir> pulse <ip> [port] [sec] -> ok\t<numDoors> | err\t<code>\t<msg>
//   biostar_tool.exe <dllDir> release <ip> [port]   -> fòse pòt la fèmen (retire tout flag)
//   biostar_tool.exe <dllDir> lock <ip> [port]      -> kòmand lock eksplisit
// Rechèch broadcast la jwenn aparèy yo menm si IP yo pa nan menm sou-rezo ak PC la.
// Bati: csc -platform:x64 -target:exe biostar_tool.cs
using System;
using System.Net;
using System.Runtime.InteropServices;

static class Native
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetDllDirectory(string path);

    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr BS2_AllocateContext();
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_Initialize(IntPtr context);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_SetDeviceSearchingTimeout(IntPtr context, uint second);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_SearchDevices(IntPtr context);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_SearchDevicesEx(IntPtr context, IntPtr hostipAddr);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetDevices(IntPtr context, out IntPtr deviceListObj, out uint numDevice);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetDeviceInfo(IntPtr context, uint deviceId, out BS2SimpleDeviceInfo deviceInfo);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_ConnectDeviceViaIP(IntPtr context, IntPtr deviceAddress, ushort devicePort, out uint deviceId);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_DisconnectDevice(IntPtr context, uint deviceId);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetAllDoor(IntPtr context, uint deviceId, out IntPtr doorObj, out uint numDoor);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_UnlockDoor(IntPtr context, uint deviceId, byte flag, IntPtr doorIds, uint doorIdCount);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_LockDoor(IntPtr context, uint deviceId, byte flag, IntPtr doorIds, uint doorIdCount);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_TimedUnlockDoor(IntPtr context, uint deviceId, byte flag, IntPtr doorIds, uint doorIdCount, uint timeout);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_ReleaseDoor(IntPtr context, uint deviceId, byte flag, IntPtr doorIds, uint doorIdCount);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void BS2_ReleaseObject(IntPtr obj);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void BS2_ReleaseContext(IntPtr context);
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct BS2SimpleDeviceInfo
{
    public uint id;
    public ushort type;
    public byte connectionMode;
    public uint ipv4Address;
    public ushort port;
    public uint maxNumOfUser;
    public byte userNameSupported;
    public byte userPhotoSupported;
    public byte pinSupported;
    public byte cardSupported;
    public byte fingerSupported;
    public byte faceSupported;
    public byte wlanSupported;
    public byte tnaSupported;
    public byte triggerActionSupported;
    public byte wiegandSupported;
    public byte imageLogSupported;
    public byte dnsSupported;
    public byte jobCodeSupported;
    public byte wiegandMultiSupported;
    public byte rs485Mode;
    public byte sslSupported;
    public byte rootCertExist;
    public byte dualIDSupported;
    public byte useAlphanumericID;
    public uint connectedIP;
    public byte phraseCodeSupported;
    public byte card1xSupported;
    public byte systemExtSupported;
    public byte voipSupported;
    public byte rs485ExSupported;
    public byte cardExSupported;
}

static class Program
{
    static IntPtr ctx = IntPtr.Zero;

    static int Init(string dllDir)
    {
        try { Native.SetDllDirectory(dllDir); } catch { }
        ctx = Native.BS2_AllocateContext();
        if (ctx == IntPtr.Zero) { Console.WriteLine("err\tsdk_init\tBS2_AllocateContext retounen null"); return -1; }
        var rc = Native.BS2_Initialize(ctx);
        if (rc < 0) { Console.WriteLine("err\tsdk_init\tBS2_Initialize: " + rc); return rc; }
        return 0;
    }

    static int Connect(string ip, ushort port, out uint deviceId)
    {
        var ptr = Marshal.StringToHGlobalAnsi(ip);
        try { return Native.BS2_ConnectDeviceViaIP(ctx, ptr, port, out deviceId); }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    static int Search()
    {
        Native.BS2_SetDeviceSearchingTimeout(ctx, 7);
        var rc = Native.BS2_SearchDevices(ctx);
        var v6 = Marshal.StringToHGlobalAnsi("FF05::2");
        try { Native.BS2_SearchDevicesEx(ctx, v6); } finally { Marshal.FreeHGlobal(v6); }
        if (rc < 0) { Console.WriteLine("err\tsearch\tBS2_SearchDevices: " + rc); return rc; }
        IntPtr list; uint count;
        rc = Native.BS2_GetDevices(ctx, out list, out count);
        if (rc < 0) { Console.WriteLine("err\tsearch\tBS2_GetDevices: " + rc); return rc; }
        Console.WriteLine("count\t" + count);
        for (uint i = 0; i < count; i++)
        {
            var id = (uint)Marshal.ReadInt32(list, (int)i * sizeof(uint));
            BS2SimpleDeviceInfo info;
            if (Native.BS2_GetDeviceInfo(ctx, id, out info) > 0)
            {
                var ip = new IPAddress(BitConverter.GetBytes(info.ipv4Address)).ToString();
                Console.WriteLine("device\t" + id + "\t" + info.type + "\t" + ip + "\t" + info.port
                    + "\tfinger=" + info.fingerSupported);
            }
            else
            {
                Console.WriteLine("device\t" + id + "\t?info");
            }
        }
        if (list != IntPtr.Zero) Native.BS2_ReleaseObject(list);
        return 0;
    }

    static int Ping(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        BS2SimpleDeviceInfo info;
        if (Native.BS2_GetDeviceInfo(ctx, id, out info) > 0)
        {
            var dip = new IPAddress(BitConverter.GetBytes(info.ipv4Address)).ToString();
            Console.WriteLine("ok\t" + id + "\t" + info.type + "\t" + dip + "\t" + info.port);
        }
        else
        {
            Console.WriteLine("ok\t" + id + "\t?\t" + ip + "\t" + port);
        }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    static int Pulse(string ip, ushort port, uint seconds)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        IntPtr doorObj; uint numDoor;
        rc = Native.BS2_GetAllDoor(ctx, id, out doorObj, out numDoor);
        if (rc < 0 || numDoor == 0)
        {
            Console.WriteLine("err\tno_door\tOkenn pòt pa konfigire sou tèminal la (code " + rc + ")");
            Native.BS2_DisconnectDevice(ctx, id);
            return -1;
        }
        // doorID se premye chan BS2Door a: eleman 0 nan tablo a se offset 0.
        // Pou yon tèminal yon sèl pòt (BioEntry W2), se sa ki kòrèk.
        var firstDoorId = Marshal.ReadInt32(doorObj, 0);
        var doorIds = Marshal.AllocHGlobal(4);
        try
        {
            Marshal.WriteInt32(doorIds, 0, firstDoorId);
            // Flag OPERATOR (0x04) tankou egzanp Suprema yo: pa janm itilize 0xFF
            // (ALL) paske li make pòt la "déverrouillée par opérateur" epi relè a
            // rete louvri san fen menm apre timeout la.
            const byte DoorFlagOperator = 0x04;
            rc = seconds > 0
                ? Native.BS2_TimedUnlockDoor(ctx, id, DoorFlagOperator, doorIds, 1, seconds)
                : Native.BS2_UnlockDoor(ctx, id, DoorFlagOperator, doorIds, 1);
        }
        finally { Marshal.FreeHGlobal(doorIds); }
        if (doorObj != IntPtr.Zero) Native.BS2_ReleaseObject(doorObj);
        Native.BS2_DisconnectDevice(ctx, id);
        if (rc < 0) { Console.WriteLine("err\tunlock_failed\tTimedUnlockDoor: " + rc); return rc; }
        Console.WriteLine("ok\t" + numDoor);
        return 0;
    }

    // Fòse pòt la fèmen touswit: retire tout flag unlock/lock (release) oswa
    // voye yon kòmand lock eksplisit. Itil pou pòt ki rete louvri apre yon
    // unlock ak move flag (ex. 0xFF).
    static int ReleaseOrLock(string ip, ushort port, bool lockOnly)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        IntPtr doorObj; uint numDoor;
        rc = Native.BS2_GetAllDoor(ctx, id, out doorObj, out numDoor);
        if (rc < 0 || numDoor == 0)
        {
            Console.WriteLine("err\tno_door\tOkenn pòt pa konfigire sou tèminal la (code " + rc + ")");
            Native.BS2_DisconnectDevice(ctx, id);
            return -1;
        }
        var firstDoorId = Marshal.ReadInt32(doorObj, 0);
        var doorIds = Marshal.AllocHGlobal(4);
        try
        {
            Marshal.WriteInt32(doorIds, 0, firstDoorId);
            rc = lockOnly
                ? Native.BS2_LockDoor(ctx, id, 0x04, doorIds, 1)
                : Native.BS2_ReleaseDoor(ctx, id, 0xFF, doorIds, 1);
        }
        finally { Marshal.FreeHGlobal(doorIds); }
        if (doorObj != IntPtr.Zero) Native.BS2_ReleaseObject(doorObj);
        Native.BS2_DisconnectDevice(ctx, id);
        if (rc < 0) { Console.WriteLine("err\tlock_failed\t" + (lockOnly ? "LockDoor" : "ReleaseDoor") + ": " + rc); return rc; }
        Console.WriteLine("ok\t" + numDoor);
        return 0;
    }

    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("err\tusage\tbiostar_tool.exe <dllDir> <search|ping|pulse|release|lock> [arg...]");
            return 1;
        }
        var rc = Init(args[0]);
        if (rc != 0) return 1;
        try
        {
            switch (args[1])
            {
                case "search":
                    return Search();
                case "ping":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tping <ip> [port]"); return 1; }
                    return Ping(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "pulse":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tpulse <ip> [port] [sec]"); return 1; }
                    return Pulse(args[2],
                        args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211,
                        args.Length > 4 ? uint.Parse(args[4]) : 3);
                case "release":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\trelease <ip> [port]"); return 1; }
                    return ReleaseOrLock(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211, false);
                case "lock":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tlock <ip> [port]"); return 1; }
                    return ReleaseOrLock(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211, true);
                default:
                    Console.WriteLine("err\tunknown_command\t" + args[1]);
                    return 1;
            }
        }
        catch (Exception e)
        {
            Console.WriteLine("err\tsdk_error\t" + e.GetType().Name + ": " + e.Message);
            return 1;
        }
        finally
        {
            if (ctx != IntPtr.Zero) Native.BS2_ReleaseContext(ctx);
        }
    }
}
