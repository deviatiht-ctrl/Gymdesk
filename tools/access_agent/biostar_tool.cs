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
using System.Collections.Generic;
using System.Linq;
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
    public static extern int BS2_GetAllDoorStatus(IntPtr context, uint deviceId, out IntPtr doorStatusObj, out uint numDoorStatus);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetUserDatabaseInfo(IntPtr context, uint deviceId, out uint numUsers, out uint numCards, out uint numFingers, out uint numFaces, IntPtr cb);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetUserList(IntPtr context, uint deviceId, out IntPtr uidsObj, out uint numUid, IntPtr cb);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_EnrollUser(IntPtr context, uint deviceId, [In, Out] BS2UserBlob[] userBlobs, uint userCount, byte overwrite);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetFingerprintConfig(IntPtr context, uint deviceId, IntPtr config);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetUserDatas(IntPtr context, uint deviceId, IntPtr uids, uint uidCount, [In, Out] BS2UserBlob[] userBlobs, uint userMask);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_RemoveUser(IntPtr context, uint deviceId, IntPtr uids, uint uidCount);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_RemoveAllUser(IntPtr context, uint deviceId);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetFilteredLog(IntPtr context, uint deviceId, IntPtr uid, ushort eventCode, uint start, uint end, byte tnaKey, out IntPtr logsObj, out uint numLog);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetLog(IntPtr context, uint deviceId, uint eventId, uint amount, out IntPtr logsObj, out uint numLog);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_GetAuthConfig(IntPtr context, uint deviceId, IntPtr config);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_VerifyFingerprint(IntPtr context, uint deviceId, IntPtr finger);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_ScanFingerprintEx(IntPtr context, uint deviceId, IntPtr finger, uint templateIndex, uint quality, byte templateFormat, out uint outQuality, IntPtr cbReadyToScan);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_StartMonitoringLog(IntPtr context, uint deviceId, IntPtr cbLogReceived);
    [DllImport("BS_SDK_V2.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int BS2_StopMonitoringLog(IntPtr context, uint deviceId);
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

// Estrikti itilizatè yo (Pack=1, menm layout ak SFStruct.cs nan SDK a).
[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct BS2User
{
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
    public byte[] userID;
    public byte formatVersion;
    public byte flag;
    public ushort version;
    public byte numCards;
    public byte numFingers;
    public byte numFaces;
    public byte infoMask;
    public uint authGroupID;
    public uint faceChecksum;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct BS2UserSetting
{
    public uint startTime;
    public uint endTime;
    public byte fingerAuthMode;   // 0 = BIOMETRIC_ONLY, 254 = PROHIBITED, 255 = NONE
    public byte cardAuthMode;
    public byte idAuthMode;
    public byte securityLevel;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct BS2UserPhoto
{
    public uint size;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16 * 1024)]
    public byte[] data;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct BS2Fingerprint
{
    public byte index;
    public byte flag;
    public ushort reserved;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2 * 384)]
    public byte[] data;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct BS2UserBlob
{
    public BS2User user;
    public BS2UserSetting setting;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 48 * 4)]
    public byte[] name;
    public BS2UserPhoto photo;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
    public byte[] pin;
    public IntPtr cardObjs;
    public IntPtr fingerObjs;
    public IntPtr faceObjs;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
    public uint[] accessGroupId;
}

static class Program
{
    static IntPtr ctx = IntPtr.Zero;
    const uint DefaultStart = 978307200;   // 2001-01-01 00:00:00
    const uint DefaultEnd = 1924991999;    // 2030-12-31 23:59:59

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
            // SOU TÈMINAL SAN KAPTEUR PÒT (sensorDevice=0), timed unlock la PA
            // ekspire: unlockFlags rete 0x04 epi relè a rete louvri san fen.
            // Nou tann dire a epi nou retire flag operatè a pou relè a tounen
            // nan eta "locked". 20s max pou ajan an pa touye pwosesis la (timeout 25s).
            if (rc >= 0 && seconds > 0)
            {
                System.Threading.Thread.Sleep((int)Math.Min(seconds, 20) * 1000);
                Native.BS2_ReleaseDoor(ctx, id, DoorFlagOperator, doorIds, 1);
            }
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

    // Li eta reyèl pòt la sou tèminal lan: BS2DoorStatus (16 bytes, pack=1):
    //   id u32 | opened u8 | unlocked u8 | heldOpened u8 | unlockFlags u8 |
    //   lockFlags u8 | alarmFlags u8 | reserved u16 | lastOpenTime u32
    // Itil pou dyagnostike pòt ki rete louvri: si unlocked=1 apre yon lock,
    // gade unlockFlags (0x01 schedule, 0x04 operator, 0x02 emergency).
    static int Status(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        // Konfig pòt la (BS2Door, pack=1): relay.deviceID @156, relay.port @160,
        // sensor.deviceID @164, sensor.port @168, sensor.switchType @169,
        // autoLockTimeout @180, unconditionalLock @191. Si relay.deviceID pa
        // id tèminal lan, pòt la kondwi yon relè remote (SIO) — pa relè entèn nan.
        IntPtr doorCfg; uint numDoorCfg;
        if (Native.BS2_GetAllDoor(ctx, id, out doorCfg, out numDoorCfg) >= 0 && numDoorCfg > 0)
        {
            var relayDev = Marshal.ReadInt32(doorCfg, 156);
            var relayPort = Marshal.ReadByte(doorCfg, 160);
            var sensorDev = Marshal.ReadInt32(doorCfg, 164);
            var sensorSw = Marshal.ReadByte(doorCfg, 169);
            var autoLock = Marshal.ReadInt32(doorCfg, 180);
            var uncondLock = Marshal.ReadByte(doorCfg, 191);
            Console.WriteLine("config\trelayDevice=" + (uint)relayDev + "\trelayPort=" + relayPort
                + "\tsensorDevice=" + (uint)sensorDev + "\tsensorSwitch=" + sensorSw
                + "\tautoLockTimeout=" + autoLock + "\tunconditionalLock=" + uncondLock
                + "\tterminalId=" + id);
            Native.BS2_ReleaseObject(doorCfg);
        }
        IntPtr statusObj; uint numStatus;
        rc = Native.BS2_GetAllDoorStatus(ctx, id, out statusObj, out numStatus);
        if (rc < 0 || numStatus == 0)
        {
            Console.WriteLine("err\tno_status\tGetAllDoorStatus: " + rc);
            Native.BS2_DisconnectDevice(ctx, id);
            return rc < 0 ? rc : -1;
        }
        for (uint i = 0; i < numStatus; i++)
        {
            var p = new IntPtr(statusObj.ToInt64() + i * 16);
            var doorId = Marshal.ReadInt32(p, 0);
            var opened = Marshal.ReadByte(p, 4);
            var unlocked = Marshal.ReadByte(p, 5);
            var held = Marshal.ReadByte(p, 6);
            var unlockFlags = Marshal.ReadByte(p, 7);
            var lockFlags = Marshal.ReadByte(p, 8);
            var alarm = Marshal.ReadByte(p, 9);
            var lastOpen = Marshal.ReadInt32(p, 12);
            Console.WriteLine("door\t" + doorId + "\topened=" + opened + "\tunlocked=" + unlocked
                + "\theld=" + held + "\tunlockFlags=0x" + unlockFlags.ToString("X2")
                + "\tlockFlags=0x" + lockFlags.ToString("X2") + "\talarm=0x" + alarm.ToString("X2")
                + "\tlastOpen=" + lastOpen);
        }
        if (statusObj != IntPtr.Zero) Native.BS2_ReleaseObject(statusObj);
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Lis sa ki sou tèminal la: kantite + ID itilizatè yo.
    // Sa montre si ansyen baz BioStar la toujou la.
    static int Users(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        uint nu, nc, nf, nfa;
        rc = Native.BS2_GetUserDatabaseInfo(ctx, id, out nu, out nc, out nf, out nfa, IntPtr.Zero);
        if (rc < 0) { Console.WriteLine("err\tdb_info\tGetUserDatabaseInfo: " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
        Console.WriteLine("db\tusers=" + nu + "\tcards=" + nc + "\tfingers=" + nf + "\tfaces=" + nfa);
        IntPtr uidsObj; uint numUid;
        rc = Native.BS2_GetUserList(ctx, id, out uidsObj, out numUid, IntPtr.Zero);
        if (rc >= 0 && uidsObj != IntPtr.Zero)
        {
            // uidsObj se yon blòk kontig: 32 bytes (BS2_USER_ID_SIZE) pa ID.
            var buf = new byte[32];
            var shown = 0u;
            for (uint i = 0; i < numUid; i++)
            {
                Marshal.Copy(new IntPtr(uidsObj.ToInt64() + i * 32), buf, 0, 32);
                var uid = System.Text.Encoding.ASCII.GetString(buf).TrimEnd('\0').Trim();
                if (shown++ < 5000) Console.WriteLine("uid\t" + uid);
            }
            if (numUid > shown) Console.WriteLine("uid\t... +" + (numUid - shown) + " lòt");
            Native.BS2_ReleaseObject(uidsObj);
        }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Pouse itilizatè + anprent GymDesk yo sou tèminal la.
    // Fichye a se liy TSV:
    //   user\t<id32>\t<non>
    //   finger\t<id32>\t<index>\t<b64 tpl1>[\t<b64 tpl2>]
    // id32 = id itilizatè ASCII max 32 karaktè (ex: UUID manm san tiret).
    static int Enroll(string ip, string file, ushort port)
    {
        var users = new Dictionary<string, BS2UserBlob>();
        var fingers = new Dictionary<string, List<BS2Fingerprint>>();
        var order = new List<string>();
        var skipped = new List<string>();
        foreach (var raw in System.IO.File.ReadAllLines(file))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith("#")) continue;
            var f = line.Split('\t');
            if (f.Length >= 3 && f[0] == "user")
            {
                var uid = f[1];
                if (!users.ContainsKey(uid))
                {
                    var blob = NewBlob(uid, f[2]);
                    // Opsyonèl: dat kòmansman/fen (epoch UTC) — W2 a refize
                    // itilizatè a li menm apre dat fen an (ACCESS_DENIED_EXPIRED).
                    uint start, end;
                    if (f.Length >= 5 && uint.TryParse(f[3], out start) && uint.TryParse(f[4], out end) && end > start)
                    {
                        blob.setting.startTime = start;
                        blob.setting.endTime = end;
                    }
                    users[uid] = blob;
                    fingers[uid] = new List<BS2Fingerprint>();
                    order.Add(uid);
                }
            }
            else if (f.Length >= 4 && f[0] == "finger" && users.ContainsKey(f[1]))
            {
                var fp = new BS2Fingerprint
                {
                    index = byte.Parse(f[2]),
                    flag = 0,
                    reserved = 0,
                    data = new byte[2 * 384],
                };
                var skip = false;
                for (var t = 0; t < 2 && 3 + t < f.Length && f[3 + t].Length > 0; t++)
                {
                    var tpl = Convert.FromBase64String(f[3 + t]);
                    if (tpl.Length > 384)
                    {
                        // Template ISO pa fòma natif Suprema: sote manm sa a
                        // san pa anpeche rès batch la.
                        Console.WriteLine("skip\t" + f[1] + "\ttemplate " + tpl.Length + "B > 384B (ISO — re-kaptire an fòma suprema)");
                        skip = true;
                        break;
                    }
                    Array.Copy(tpl, 0, fp.data, t * 384, tpl.Length);
                }
                // W2 a bezwen 2 template pa dwèt pou identify mache —
                // si gen 1 sèl, kopye l nan dezyèm plas la.
                if (!skip)
                {
                    var empty = true;
                    for (var b = 384; b < 768; b++) if (fp.data[b] != 0) { empty = false; break; }
                    if (empty) Array.Copy(fp.data, 0, fp.data, 384, 384);
                }
                if (skip) skipped.Add(f[1]); else fingers[f[1]].Add(fp);
            }
        }
        order.RemoveAll(u => skipped.Contains(u));
        if (order.Count == 0) { Console.WriteLine("err\tempty\tOkenn itilizatè nan fichye a"); return -1; }

        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }

        var blobs = order.Select(u => users[u]).ToArray();
        var fingerPtrs = new List<IntPtr>();
        try
        {
            for (var i = 0; i < order.Count; i++)
            {
                var fps = fingers[order[i]];
                if (fps.Count == 0) continue;
                var ptr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(BS2Fingerprint)) * fps.Count);
                fingerPtrs.Add(ptr);
                for (var j = 0; j < fps.Count; j++)
                    Marshal.StructureToPtr(fps[j], new IntPtr(ptr.ToInt64() + j * Marshal.SizeOf(typeof(BS2Fingerprint))), false);
                blobs[i].fingerObjs = ptr;
                blobs[i].user.numFingers = (byte)fps.Count;
            }
            rc = Native.BS2_EnrollUser(ctx, id, blobs, (uint)blobs.Length, 1);
        }
        finally
        {
            foreach (var p in fingerPtrs) Marshal.FreeHGlobal(p);
        }
        Native.BS2_DisconnectDevice(ctx, id);
        if (rc < 0) { Console.WriteLine("err\tenroll_failed\tBS2_EnrollUser: " + rc); return rc; }
        Console.WriteLine("ok\t" + order.Count);
        return 0;
    }

    static BS2UserBlob NewBlob(string uid, string name)
    {
        var blob = new BS2UserBlob
        {
            user = new BS2User
            {
                userID = new byte[32],
                formatVersion = 0,
                flag = 0,
                version = 0,
                numCards = 0,
                numFingers = 0,
                numFaces = 0,
                infoMask = 0,
            },
            setting = new BS2UserSetting
            {
                // Valè default BioStar 2 (2001-01-01 → 2030-12-31 23:59:59).
                // ATANSYON: endTime=0xFFFFFFFF/startTime=0 = W2 a trete l kòm
                // ekspire (ACCESS_DENIED_EXPIRED 0x1903, verifye sou W2 a).
                startTime = DefaultStart,
                endTime = DefaultEnd,
                fingerAuthMode = 255,   // NONE → itilize mòd default tèminal la
                cardAuthMode = 255,     // (menm jan ak itilizatè BioStar yo)
                idAuthMode = 255,
                securityLevel = 0,
            },
            name = new byte[48 * 4],
            photo = new BS2UserPhoto { size = 0, data = new byte[16 * 1024] },
            pin = new byte[32],
            cardObjs = IntPtr.Zero,
            fingerObjs = IntPtr.Zero,
            faceObjs = IntPtr.Zero,
            accessGroupId = new uint[16],
        };
        var uidBytes = System.Text.Encoding.ASCII.GetBytes(uid);
        Array.Copy(uidBytes, 0, blob.user.userID, 0, Math.Min(uidBytes.Length, 32));
        var nameBytes = System.Text.Encoding.UTF8.GetBytes(name ?? "");
        Array.Copy(nameBytes, 0, blob.name, 0, Math.Min(nameBytes.Length, 48 * 4 - 1));
        return blob;
    }

    // Li BS2FingerprintConfig tèminal la: templateFormat @ offset 4
    // (0=SUPREMA, 1=ISO, 2=ANSI). Enroll bezwen template nan menm fòma —
    // chanje l ta kraze tout anprent ki deja sou tèminal la.
    static int FpConfig(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var buf = Marshal.AllocHGlobal(64);
        try
        {
            for (var i = 0; i < 64; i++) Marshal.WriteByte(buf, i, 0);
            rc = Native.BS2_GetFingerprintConfig(ctx, id, buf);
            if (rc < 0) { Console.WriteLine("err\tfpconfig\tGetFingerprintConfig: " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
            var fmt = Marshal.ReadByte(buf, 4);
            var name = fmt == 0 ? "SUPREMA" : fmt == 1 ? "ISO" : fmt == 2 ? "ANSI" : "?";
            Console.WriteLine("fpconfig\ttemplateFormat=" + fmt + "(" + name + ")"
                + "\tsecurityLevel=" + Marshal.ReadByte(buf, 0)
                + "\tfastMode=" + Marshal.ReadByte(buf, 1));
        }
        finally { Marshal.FreeHGlobal(buf); }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Ekstrè anprent yon itilizatè ki sou tèminal la (fòma natif) —
    // itil pou teste/tèminal → fichye enroll.
    static int PullFp(string ip, string uid, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var uids = Marshal.AllocHGlobal(32);
        var blobs = new BS2UserBlob[] { NewBlob("", "") };
        try
        {
            var ub = System.Text.Encoding.ASCII.GetBytes(uid);
            for (var i = 0; i < 32; i++) Marshal.WriteByte(uids, i, i < ub.Length ? ub[i] : (byte)0);
            rc = Native.BS2_GetUserDatas(ctx, id, uids, 1, blobs, 0xFFFF); // ALL mask
            if (rc < 0) { Console.WriteLine("err\tget_user\t" + uid + ": " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
            var name = System.Text.Encoding.UTF8.GetString(blobs[0].name).TrimEnd('\0').Trim();
            var groups = string.Join(",", blobs[0].accessGroupId.Where(g => g != 0));
            Console.WriteLine("user\t" + uid + "\t" + name + "\tnumFingers=" + blobs[0].user.numFingers
                + "\tstart=" + blobs[0].setting.startTime + "\tend=" + blobs[0].setting.endTime
                + "\tfingerAuth=" + blobs[0].setting.fingerAuthMode
                + "\tcardAuth=" + blobs[0].setting.cardAuthMode
                + "\tidAuth=" + blobs[0].setting.idAuthMode
                + "\taccessGroups=[" + groups + "]");
            if (blobs[0].fingerObjs != IntPtr.Zero && blobs[0].user.numFingers > 0)
            {
                var n = blobs[0].user.numFingers;
                for (var i = 0; i < n && i < 10; i++)
                {
                    var fp = new IntPtr(blobs[0].fingerObjs.ToInt64() + i * 772);
                    var idx = Marshal.ReadByte(fp, 0);
                    var data = new byte[768];
                    Marshal.Copy(new IntPtr(fp.ToInt64() + 4), data, 0, 768);
                    var t1 = new byte[384]; Array.Copy(data, 0, t1, 0, 384);
                    var t2 = new byte[384]; Array.Copy(data, 384, t2, 0, 384);
                    var used1 = t1.Any(b => b != 0);
                    var used2 = t2.Any(b => b != 0);
                    Console.WriteLine("finger\t" + uid + "\t" + idx
                        + "\t" + (used1 ? Convert.ToBase64String(t1) : "")
                        + (used2 ? "\t" + Convert.ToBase64String(t2) : ""));
                }
                Native.BS2_ReleaseObject(blobs[0].fingerObjs);
            }
            if (blobs[0].cardObjs != IntPtr.Zero) Native.BS2_ReleaseObject(blobs[0].cardObjs);
            if (blobs[0].faceObjs != IntPtr.Zero) Native.BS2_ReleaseObject(blobs[0].faceObjs);
        }
        finally { Marshal.FreeHGlobal(uids); }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Eskane yon dwèt sou W2 a epi verifye l kont template itilizatè <uid>
    // ki deja sou tèminal la. Sa di nou si matchè tèminal la ka li template
    // nou pouse yo (tès konpatiblite fòma), san wèl pòt la.
    static int VScan(string ip, string uid, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var uids = Marshal.AllocHGlobal(32);
        var fp = Marshal.AllocHGlobal(772);
        var blobs = new BS2UserBlob[] { NewBlob("", "") };
        try
        {
            var ub = System.Text.Encoding.ASCII.GetBytes(uid);
            for (var i = 0; i < 32; i++) Marshal.WriteByte(uids, i, i < ub.Length ? ub[i] : (byte)0);
            rc = Native.BS2_GetUserDatas(ctx, id, uids, 1, blobs, 0xFFFF); // ALL mask
            if (rc < 0) { Console.WriteLine("err\tget_user\t" + uid + ": " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
            if (blobs[0].fingerObjs == IntPtr.Zero || blobs[0].user.numFingers == 0)
            {
                Console.WriteLine("err\tno_finger\t" + uid + " pa gen anprent sou tèminal la");
                Native.BS2_DisconnectDevice(ctx, id);
                return -1;
            }
            // Kopye premye BS2Fingerprint (772 bytes) nan buffer nou an.
            for (var i = 0; i < 772; i++) Marshal.WriteByte(fp, i, Marshal.ReadByte(blobs[0].fingerObjs, i));
            Native.BS2_ReleaseObject(blobs[0].fingerObjs);
            if (blobs[0].cardObjs != IntPtr.Zero) Native.BS2_ReleaseObject(blobs[0].cardObjs);
            if (blobs[0].faceObjs != IntPtr.Zero) Native.BS2_ReleaseObject(blobs[0].faceObjs);

            Console.Error.WriteLine("[vscan] Mete dwèt la sou Capteur W2 a kounye a...");
            rc = Native.BS2_VerifyFingerprint(ctx, id, fp);
            if (rc > 0) Console.WriteLine("ok\tmatch\tDWÈT LA MATCHE — matchè W2 a ka li template sa a.");
            else if (rc == -307) Console.WriteLine("err\tno_match\tNOT_SAME_FINGERPRINT (-307): dwèt la pa matche template sa a.");
            else Console.WriteLine("err\tverify\tBS2_VerifyFingerprint: " + rc);
        }
        finally { Marshal.FreeHGlobal(fp); Marshal.FreeHGlobal(uids); }
        Native.BS2_DisconnectDevice(ctx, id);
        return rc;
    }

    // Callback: W2 a rele sa lè li pare pou yon eskan — se SINYAL reyèl
    // "mete dwèt la" la. Kenbe referans lan vivan pandan eskan an (GC).
    static OnReadyToScanDelegate readyCb = new OnReadyToScanDelegate(OnReadyToScan);
    delegate void OnReadyToScanDelegate(uint deviceId, uint sequence);
    static void OnReadyToScan(uint deviceId, uint sequence)
    {
        Console.Error.WriteLine("[scan] >>> W2 PARE — METE DWÈT LA SOU KAPTEUR LA KOUNYE A <<<");
        Console.Error.Flush();
    }

    // Callback monitoring: chak evènman W2 a (auth, pòt, itilizatè) parèt
    // la an tan reyèl — meyè fason pou wè sa tèminal la fè ak yon eskan.
    static OnLogReceivedDelegate logCb = new OnLogReceivedDelegate(OnLogReceived);
    delegate void OnLogReceivedDelegate(uint deviceId, IntPtr eventPtr);
    static void OnLogReceived(uint deviceId, IntPtr p)
    {
        try
        {
            var evId = (uint)Marshal.ReadInt32(p, 0);
            var ts = (uint)Marshal.ReadInt32(p, 4);
            var dev = (uint)Marshal.ReadInt32(p, 8);
            var uidBytes = new byte[32];
            Marshal.Copy(new IntPtr(p.ToInt64() + 12), uidBytes, 0, 32);
            var uid = System.Text.Encoding.ASCII.GetString(uidBytes).TrimEnd('\0').Trim();
            var code = (ushort)Marshal.ReadInt16(p, 44);
            var param = Marshal.ReadByte(p, 46);
            var dt = ts == 0 ? "-" : new DateTime(1970, 1, 1).AddSeconds(ts).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
            Console.WriteLine("evt\t" + evId + "\t" + dt + "\tdev=" + dev
                + "\tuid=" + (uid.Length > 0 ? uid : "-")
                + "\tcode=0x" + code.ToString("X4") + "\t" + EvName(code) + "\tparam=" + param);
            Console.Out.Flush();
        }
        catch { }
    }

    // Siveye evènman W2 yo pandan <seconds> segonn (0 = san fen) — mete
    // dwèt sou tèminal la pou wè si l rekonèt ou oswa l refize.
    // [cmdDir]: ajan an depoze fichye *.cmd ("pulse 3" | "release" | "lock")
    // pou pòt la egzekite sou MENM koneksyon an (pa gen 2yèm koneksyon,
    // pa gen evènman ki pèdi). Rezilta a ekri nan <non>.res.
    static int Watch(string ip, ushort port, int seconds, string cmdDir)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var cbPtr = Marshal.GetFunctionPointerForDelegate(logCb);
        rc = Native.BS2_StartMonitoringLog(ctx, id, cbPtr);
        if (rc <= 0) { Console.WriteLine("err\twatch\tStartMonitoringLog: " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
        int doorId = 0;
        IntPtr doorObj; uint numDoor;
        if (Native.BS2_GetAllDoor(ctx, id, out doorObj, out numDoor) >= 0 && numDoor > 0)
        {
            doorId = Marshal.ReadInt32(doorObj, 0);
            Native.BS2_ReleaseObject(doorObj);
        }
        Console.WriteLine("watching\t" + id + "\tdoor=" + doorId);
        Console.Out.Flush();
        Console.Error.WriteLine("[watch] Siveyan aktive" + (seconds > 0 ? " pandan " + seconds + "s" : "") + " — eskane dwèt la sou W2 a kounye a...");
        var started = DateTime.UtcNow;
        var lastBeat = DateTime.UtcNow;
        var exitCode = 0;
        while (seconds <= 0 || (DateTime.UtcNow - started).TotalSeconds < seconds)
        {
            System.Threading.Thread.Sleep(150);
            if (cmdDir != null && System.IO.Directory.Exists(cmdDir))
            {
                foreach (var file in System.IO.Directory.GetFiles(cmdDir, "*.cmd"))
                {
                    string cmd;
                    try { cmd = System.IO.File.ReadAllText(file).Trim(); System.IO.File.Delete(file); }
                    catch { continue; }
                    var resFile = System.IO.Path.ChangeExtension(file, ".res");
                    var capturedDoor = doorId;
                    var deviceId = id;
                    new System.Threading.Thread(() => RunDoorCommand(deviceId, capturedDoor, cmd, resFile)) { IsBackground = true }.Start();
                }
            }
            if ((DateTime.UtcNow - lastBeat).TotalSeconds >= 20)
            {
                lastBeat = DateTime.UtcNow;
                BS2SimpleDeviceInfo info;
                if (Native.BS2_GetDeviceInfo(ctx, id, out info) <= 0)
                {
                    // Tèminal la dekonekte: kite ajan an relanse siveyan an.
                    Console.WriteLine("err\tdisconnected\tTèminal la pa reponn ankò");
                    Console.Out.Flush();
                    exitCode = 2;
                    break;
                }
            }
        }
        Native.BS2_StopMonitoringLog(ctx, id);
        Native.BS2_DisconnectDevice(ctx, id);
        return exitCode;
    }

    static void RunDoorCommand(uint id, int doorId, string cmd, string resFile)
    {
        string result;
        if (doorId == 0) result = "err\tno_door\tOkenn pòt pa konfigire sou tèminal la";
        else
        {
            var parts = cmd.Split(' ');
            var doorIds = Marshal.AllocHGlobal(4);
            try
            {
                Marshal.WriteInt32(doorIds, 0, doorId);
                int rc;
                if (parts[0] == "pulse")
                {
                    uint seconds = 3;
                    if (parts.Length > 1) uint.TryParse(parts[1], out seconds);
                    seconds = Math.Max(1u, Math.Min(seconds, 20u));
                    rc = Native.BS2_TimedUnlockDoor(ctx, id, 0x04, doorIds, 1, seconds);
                    if (rc >= 0)
                    {
                        // Menm koreksyon ak Pulse(): san kapteur pòt, timed unlock
                        // la pa ekspire — nou retire flag operatè a apre dire a.
                        System.IO.File.WriteAllText(resFile, "ok\t1");
                        System.Threading.Thread.Sleep((int)seconds * 1000);
                        Native.BS2_ReleaseDoor(ctx, id, 0x04, doorIds, 1);
                        return;
                    }
                }
                else if (parts[0] == "lock") rc = Native.BS2_LockDoor(ctx, id, 0x04, doorIds, 1);
                else rc = Native.BS2_ReleaseDoor(ctx, id, 0xFF, doorIds, 1);
                result = rc >= 0 ? "ok\t1" : "err\tdoor\t" + parts[0] + ": " + rc;
            }
            finally { Marshal.FreeHGlobal(doorIds); }
        }
        try { System.IO.File.WriteAllText(resFile, result); } catch { }
    }

    // Eskane yon dwèt sou W2 a (fòma natif SUPREMA) epi afiche template yo
    // an base64 — pou pwodwi template ki soti dirèkteman sou tèminal la.
    static int SScan(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var fp = Marshal.AllocHGlobal(772);
        var cbPtr = Marshal.GetFunctionPointerForDelegate(readyCb);
        try
        {
            for (var i = 0; i < 772; i++) Marshal.WriteByte(fp, i, 0);
            for (uint t = 0; t < 2; t++)
            {
                var ok = false;
                for (var attempt = 1; attempt <= 3 && !ok; attempt++)
                {
                    uint q;
                    Console.Error.WriteLine("[sscan] Template " + (t + 1) + "/2, tantativ " + attempt + " — tann sinyal W2 a...");
                    rc = Native.BS2_ScanFingerprintEx(ctx, id, fp, t, 40, 0, out q, cbPtr);
                    if (rc > 0)
                    {
                        Console.Error.WriteLine("[sscan] t" + t + " ok quality=" + q);
                        var tpl = new byte[384];
                        Marshal.Copy(new IntPtr(fp.ToInt64() + 4 + t * 384), tpl, 0, 384);
                        Console.WriteLine("fp\t" + Convert.ToBase64String(tpl));
                        Console.Out.Flush();
                        ok = true;
                    }
                    else if (rc == -305)
                    {
                        Console.Error.WriteLine("[sscan] timeout — pa gen dwèt. Rekòmanse...");
                    }
                    else if (rc == -308 || rc == -309)
                    {
                        Console.Error.WriteLine("[sscan] kalite twò ba — peze dwèt la byen plat, rekòmanse...");
                    }
                    else
                    {
                        Console.WriteLine("err\tscan\tBS2_ScanFingerprintEx t" + t + ": " + rc);
                        Native.BS2_DisconnectDevice(ctx, id);
                        return rc;
                    }
                }
                if (!ok)
                {
                    Console.WriteLine("err\tscan\tTemplate " + (t + 1) + " echwe apre 3 tantativ");
                    Native.BS2_DisconnectDevice(ctx, id);
                    return -1;
                }
            }
        }
        finally { Marshal.FreeHGlobal(fp); }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Enroll yon itilizatè antye pa eskane dwèt la sou W2 a: eskane 2
    // template yo sou tèminal la menm epi anrejistre l dirèkteman.
    // Template la garanti konpatib — se W2 a ki pwodwi l.
    static int EnrollScan(string ip, string uid, string name, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var fp = Marshal.AllocHGlobal(772);
        var cbPtr = Marshal.GetFunctionPointerForDelegate(readyCb);
        try
        {
            for (var i = 0; i < 772; i++) Marshal.WriteByte(fp, i, 0);
            for (uint t = 0; t < 2; t++)
            {
                var ok = false;
                for (var attempt = 1; attempt <= 3 && !ok; attempt++)
                {
                    uint q;
                    Console.Error.WriteLine("[enrollscan] Template " + (t + 1) + "/2, tantativ " + attempt + " — tann sinyal W2 a...");
                    rc = Native.BS2_ScanFingerprintEx(ctx, id, fp, t, 40, 0, out q, cbPtr);
                    if (rc > 0) { Console.Error.WriteLine("[enrollscan] t" + t + " ok quality=" + q); ok = true; }
                    else if (rc == -305) Console.Error.WriteLine("[enrollscan] timeout — pa gen dwèt. Rekòmanse...");
                    else if (rc == -308 || rc == -309) Console.Error.WriteLine("[enrollscan] kalite twò ba — peze dwèt la byen plat...");
                    else
                    {
                        Console.WriteLine("err\tscan\tBS2_ScanFingerprintEx t" + t + ": " + rc);
                        Native.BS2_DisconnectDevice(ctx, id);
                        return rc;
                    }
                }
                if (!ok)
                {
                    Console.WriteLine("err\tscan\tTemplate " + (t + 1) + " echwe apre 3 tantativ");
                    Native.BS2_DisconnectDevice(ctx, id);
                    return -1;
                }
            }

            var blob = NewBlob(uid, name);
            blob.user.numFingers = 1;
            var fptr = Marshal.AllocHGlobal(772);
            try
            {
                for (var i = 0; i < 772; i++) Marshal.WriteByte(fptr, i, Marshal.ReadByte(fp, i));
                blob.fingerObjs = fptr;
                var blobs = new BS2UserBlob[] { blob };
                rc = Native.BS2_EnrollUser(ctx, id, blobs, 1, 1);
            }
            finally { Marshal.FreeHGlobal(fptr); }
            if (rc < 0) { Console.WriteLine("err\tenroll\tBS2_EnrollUser: " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
            Console.WriteLine("ok\tenrolled\t" + uid);
        }
        finally { Marshal.FreeHGlobal(fp); }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Dènye evènman yo sou tèminal la (dyagnostik auth: verify fail vs
    // access denied vs pa gen scan ditou). BS2Event = 48 bytes (pack=1):
    //   id u32 @0 | ts u32 @4 | deviceID u32 @8 | userID[32] @12 |
    //   code u16 @44 (mainCode hi, subCode lo) | param u8 @46 | image u8 @47
    static string EvName(ushort code)
    {
        switch (code & 0xFF00)
        {
            case 0x1000: return "VERIFY_SUCCESS";
            case 0x1100: return "VERIFY_FAIL";
            case 0x1200: return "VERIFY_DURESS";
            case 0x1300: return "IDENTIFY_SUCCESS";
            case 0x1400: return "IDENTIFY_FAIL";
            case 0x1500: return "IDENTIFY_DURESS";
            case 0x1600: return "DUAL_AUTH_SUCCESS";
            case 0x1700: return "DUAL_AUTH_FAIL";
            case 0x1800: return "AUTH_FAILED";
            case 0x1900: return "ACCESS_DENIED";
            case 0x1A00: return "FAKE_FINGER";
            case 0x2000: return "ENROLL_SUCCESS";
            case 0x2100: return "ENROLL_FAIL";
            case 0x2200: return "USER_UPDATE";
            case 0x2400: return "USER_DELETE";
            case 0x2800: return "DUPLICATE_CREDENTIAL";
            case 0x5000: return "DOOR_UNLOCKED";
            case 0x5100: return "DOOR_LOCKED";
            case 0x5200: return "DOOR_OPENED";
            case 0x5300: return "DOOR_CLOSED";
            case 0x5400: return "DOOR_FORCED_OPEN";
            case 0x5500: return "DOOR_HELD_OPEN";
            case 0x5D00: return "DOOR_LOCK_REQ";
            case 0x5E00: return "DOOR_UNLOCK_REQ";
            case 0x5F00: return "DOOR_SEND";
            case 0x3100: return "SYSTEM_STARTED";
            case 0x3900: return "COMM_LOCKED";
            case 0x3A00: return "COMM_UNLOCKED";
            case 0x3B00: return "TCP_CONNECTED";
            case 0x3C00: return "TCP_DISCONNECTED";
            case 0x4400: return "AUTH_MODE";       // dev auth config change
            case 0x4600: return "INPUT_CLEAR";
            case 0x4700: return "INPUT_DETECTED";
            default: return "EV_0x" + (code & 0xFF00).ToString("X4");
        }
    }

    static int Logs(string ip, ushort port, uint amount)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        // BS2_GetLog mache pa paj soti nan yon eventId. Nou ekri chak liy
        // touswit (flush) pou rezilta a siviv si pwosesis la kraze pita.
        const uint pageSize = 1024;
        uint lastId = 0;
        uint total = 0;
        for (var pages = 0; pages < 300; pages++)
        {
            IntPtr logsObj; uint numLog;
            rc = Native.BS2_GetLog(ctx, id, lastId, pageSize, out logsObj, out numLog);
            if (rc < 0) { Console.WriteLine("err\tlogs\tGetLog: " + rc); Console.Out.Flush(); Native.BS2_DisconnectDevice(ctx, id); return rc; }
            if (numLog == 0 || logsObj == IntPtr.Zero) { if (logsObj != IntPtr.Zero) Native.BS2_ReleaseObject(logsObj); break; }
            if (pages == 0)
            {
                var raw = new byte[256];
                Marshal.Copy(logsObj, raw, 0, 256);
                Console.Error.WriteLine("[logs] numLog=" + numLog + " raw0-255=" + BitConverter.ToString(raw));
            }
            for (uint i = 0; i < numLog; i++)
            {
                var p = new IntPtr(logsObj.ToInt64() + i * 48);
                var evId = (uint)Marshal.ReadInt32(p, 0);
                var ts = (uint)Marshal.ReadInt32(p, 4);
                var dev = (uint)Marshal.ReadInt32(p, 8);
                var uidBytes = new byte[32];
                Marshal.Copy(new IntPtr(p.ToInt64() + 12), uidBytes, 0, 32);
                var uid = System.Text.Encoding.ASCII.GetString(uidBytes).TrimEnd('\0').Trim();
                var code = (ushort)Marshal.ReadInt16(p, 44);
                var param = Marshal.ReadByte(p, 46);
                var dt = ts == 0 ? "-" : new DateTime(1970, 1, 1).AddSeconds(ts).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
                Console.WriteLine("log\t" + evId + "\t" + dt + "\tdev=" + dev
                    + "\tuid=" + (uid.Length > 0 ? uid : "-")
                    + "\tcode=0x" + code.ToString("X4") + "\t" + EvName(code) + "\tparam=" + param);
                lastId = evId; total++;
            }
            Native.BS2_ReleaseObject(logsObj);
            Console.Out.Flush();
            if (numLog < pageSize) break;
        }
        Console.WriteLine("total\t" + total);
        Console.Out.Flush();
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    // Li BS2AuthConfig tèminal la (~444 bytes, pack=1):
    //   authSchedule[11] u32 @0 | useGlobalAPB @44 | globalAPBFailAction @45
    //   useGroupMatching @46 | reserved @47 | reserved2[28] @48 | usePrivateAuth @76
    //   faceDetectionLevel @77 | useServerMatching @78 | useFullAccess @79
    //   matchTimeout @80 | authTimeout @81 | numOperators @82
    // Si useServerMatching=1, tèminal lan pa verifye lokalman — li voye
    // anprent la sou yon sèvè BioStar (si sèvè a pa la, auth pa janm mache).
    static int AuthCfg(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var buf = Marshal.AllocHGlobal(512);
        try
        {
            for (var i = 0; i < 512; i++) Marshal.WriteByte(buf, i, 0);
            rc = Native.BS2_GetAuthConfig(ctx, id, buf);
            if (rc < 0) { Console.WriteLine("err\tauthcfg\tGetAuthConfig: " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
            var sched = new List<string>();
            for (var m = 0; m < 11; m++)
            {
                var s = (uint)Marshal.ReadInt32(buf, m * 4);
                if (s != 0) sched.Add("mode" + m + "=" + s);
            }
            Console.WriteLine("authcfg\tserverMatching=" + Marshal.ReadByte(buf, 78)
                + "\tfullAccess=" + Marshal.ReadByte(buf, 79)
                + "\tgroupMatching=" + Marshal.ReadByte(buf, 46)
                + "\tprivateAuth=" + Marshal.ReadByte(buf, 76)
                + "\tauthTimeout=" + Marshal.ReadByte(buf, 81)
                + "\tschedules=[" + string.Join(" ", sched) + "]");
        }
        finally { Marshal.FreeHGlobal(buf); }
        Native.BS2_DisconnectDevice(ctx, id);
        return 0;
    }

    static int RmUser(string ip, string uid, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        var uids = Marshal.AllocHGlobal(32);
        try
        {
            var ub = System.Text.Encoding.ASCII.GetBytes(uid);
            for (var i = 0; i < 32; i++) Marshal.WriteByte(uids, i, i < ub.Length ? ub[i] : (byte)0);
            rc = Native.BS2_RemoveUser(ctx, id, uids, 1);
        }
        finally { Marshal.FreeHGlobal(uids); }
        Native.BS2_DisconnectDevice(ctx, id);
        if (rc < 0) { Console.WriteLine("err\tremove\t" + uid + ": " + rc); return rc; }
        Console.WriteLine("ok\t" + uid);
        return 0;
    }

    static int ClearUsers(string ip, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }
        rc = Native.BS2_RemoveAllUser(ctx, id);
        Native.BS2_DisconnectDevice(ctx, id);
        if (rc < 0) { Console.WriteLine("err\tremove_all\tBS2_RemoveAllUser: " + rc); return rc; }
        Console.WriteLine("ok\tcleared\tTout anprent ak itilizatè sou tèminal la efase nèt.");
        return 0;
    }

    static int DumpAll(string ip, string outFile, ushort port)
    {
        uint id;
        var rc = Connect(ip, port, out id);
        if (rc < 0) { Console.WriteLine("err\tunreachable\t" + ip + ":" + port + " pa reponn (code " + rc + ")"); return rc; }

        uint nu, nc, nf, nfa;
        rc = Native.BS2_GetUserDatabaseInfo(ctx, id, out nu, out nc, out nf, out nfa, IntPtr.Zero);
        if (rc < 0) { Console.WriteLine("err\tdb_info\tGetUserDatabaseInfo: " + rc); Native.BS2_DisconnectDevice(ctx, id); return rc; }
        Console.WriteLine("db\tusers=" + nu + "\tcards=" + nc + "\tfingers=" + nf);

        IntPtr uidsObj; uint numUid;
        rc = Native.BS2_GetUserList(ctx, id, out uidsObj, out numUid, IntPtr.Zero);
        if (rc < 0 || uidsObj == IntPtr.Zero || numUid == 0)
        {
            Console.WriteLine("ok\tempty\tOkenn itilizatè pa genyen sou tèminal la.");
            Native.BS2_DisconnectDevice(ctx, id);
            return 0;
        }

        var lines = new List<string>();
        var jsonItems = new List<string>();
        var uids = Marshal.AllocHGlobal(32);
        var blobs = new BS2UserBlob[] { NewBlob("", "") };

        try
        {
            for (uint i = 0; i < numUid; i++)
            {
                var p = new IntPtr(uidsObj.ToInt64() + i * 32);
                for (var b = 0; b < 32; b++) Marshal.WriteByte(uids, b, Marshal.ReadByte(p, b));

                rc = Native.BS2_GetUserDatas(ctx, id, uids, 1, blobs, 0xFFFF);
                if (rc < 0) continue;

                var uid = System.Text.Encoding.ASCII.GetString(blobs[0].user.userID).TrimEnd('\0').Trim();
                var name = System.Text.Encoding.UTF8.GetString(blobs[0].name).TrimEnd('\0').Trim();
                var startSec = blobs[0].setting.startTime;
                var endSec = blobs[0].setting.endTime;

                DateTime? startDt = null;
                DateTime? endDt = null;
                try { if (startSec > 0 && startSec < 0x7FFFFFFF) startDt = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(startSec); } catch { }
                try { if (endSec > 0 && endSec < 0x7FFFFFFF) endDt = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(endSec); } catch { }

                var startDateStr = startDt.HasValue ? startDt.Value.ToString("yyyy-MM-dd") : "";
                var endDateStr = endDt.HasValue ? endDt.Value.ToString("yyyy-MM-dd") : "";

                string fpB64 = "";
                if (blobs[0].fingerObjs != IntPtr.Zero && blobs[0].user.numFingers > 0)
                {
                    var fp = blobs[0].fingerObjs;
                    var data = new byte[384];
                    Marshal.Copy(new IntPtr(fp.ToInt64() + 4), data, 0, 384);
                    if (data.Any(x => x != 0)) fpB64 = Convert.ToBase64String(data);
                    Native.BS2_ReleaseObject(blobs[0].fingerObjs);
                }
                if (blobs[0].cardObjs != IntPtr.Zero) Native.BS2_ReleaseObject(blobs[0].cardObjs);
                if (blobs[0].faceObjs != IntPtr.Zero) Native.BS2_ReleaseObject(blobs[0].faceObjs);

                if (!string.IsNullOrEmpty(fpB64))
                {
                    lines.Add("finger\t" + uid + "\t0\t" + fpB64 + "\t" + name);
                    if (!string.IsNullOrEmpty(name))
                    {
                        lines.Add(name + "\t" + fpB64);
                    }
                }

                jsonItems.Add("  {\"uid\":\"" + uid + "\",\"name\":\"" + name.Replace("\"", "\\\"") 
                    + "\",\"start_date\":\"" + startDateStr + "\",\"end_date\":\"" + endDateStr + "\",\"fingerprint\":\"" + fpB64 + "\"}");

                Console.WriteLine("user\t" + uid + "\t" + name + "\tend=" + endDateStr + "\tfinger=" + (!string.IsNullOrEmpty(fpB64) ? "WI" : "NON"));
            }
        }
        finally
        {
            Marshal.FreeHGlobal(uids);
            if (uidsObj != IntPtr.Zero) Native.BS2_ReleaseObject(uidsObj);
        }

        Native.BS2_DisconnectDevice(ctx, id);

        var txtFile = string.IsNullOrEmpty(outFile) ? "anprent_bw2_export.txt" : outFile;
        var jsonFile = System.IO.Path.ChangeExtension(txtFile, ".json");

        System.IO.File.WriteAllLines(txtFile, lines);
        System.IO.File.WriteAllText(jsonFile, "[\n" + string.Join(",\n", jsonItems) + "\n]\n");

        Console.WriteLine("ok\texported\t" + lines.Count + " anprent sove nan " + txtFile + " ak " + jsonFile);
        return 0;
    }

    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("err\tusage\tbiostar_tool.exe <dllDir> <search|ping|pulse|release|lock|status|users|enroll> [arg...]");
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
                case "status":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tstatus <ip> [port]"); return 1; }
                    return Status(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "users":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tusers <ip> [port]"); return 1; }
                    return Users(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "enroll":
                    if (args.Length < 4) { Console.WriteLine("err\tusage\tenroll <ip> <file> [port]"); return 1; }
                    return Enroll(args[2], args[3], args.Length > 4 ? ushort.Parse(args[4]) : (ushort)51211);
                case "fpconfig":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tfpconfig <ip> [port]"); return 1; }
                    return FpConfig(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "pullfp":
                    if (args.Length < 4) { Console.WriteLine("err\tusage\tpullfp <ip> <uid> [port]"); return 1; }
                    return PullFp(args[2], args[3], args.Length > 4 ? ushort.Parse(args[4]) : (ushort)51211);
                case "rmuser":
                    if (args.Length < 4) { Console.WriteLine("err\tusage\trmuser <ip> <uid> [port]"); return 1; }
                    return RmUser(args[2], args[3], args.Length > 4 ? ushort.Parse(args[4]) : (ushort)51211);
                case "clearusers":
                case "rmall":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tclearusers <ip> [port]"); return 1; }
                    return ClearUsers(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "dump":
                case "export":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tdump <ip> [outputFile] [port]"); return 1; }
                    ushort testPort;
                    var outF = args.Length > 3 && !ushort.TryParse(args[3], out testPort) ? args[3] : "anprent_bw2_export.txt";
                    ushort pDump = 51211;
                    if (args.Length > 4 && ushort.TryParse(args[4], out testPort)) pDump = testPort;
                    else if (args.Length > 3 && ushort.TryParse(args[3], out testPort)) pDump = testPort;
                    return DumpAll(args[2], outF, pDump);
                case "logs":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tlogs <ip> [port] [count]"); return 1; }
                    return Logs(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211,
                        args.Length > 4 ? uint.Parse(args[4]) : 30);
                case "authcfg":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tauthcfg <ip> [port]"); return 1; }
                    return AuthCfg(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "vscan":
                    if (args.Length < 4) { Console.WriteLine("err\tusage\tvscan <ip> <uid> [port]"); return 1; }
                    return VScan(args[2], args[3], args.Length > 4 ? ushort.Parse(args[4]) : (ushort)51211);
                case "sscan":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\tsscan <ip> [port]"); return 1; }
                    return SScan(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211);
                case "watch":
                    if (args.Length < 3) { Console.WriteLine("err\tusage\twatch <ip> [port] [seconds] [cmdDir]"); return 1; }
                    return Watch(args[2], args.Length > 3 ? ushort.Parse(args[3]) : (ushort)51211,
                        args.Length > 4 ? int.Parse(args[4]) : 30, args.Length > 5 ? args[5] : null);
                case "enrollscan":
                    if (args.Length < 4) { Console.WriteLine("err\tusage\tenrollscan <ip> <uid> [name] [port]"); return 1; }
                    return EnrollScan(args[2], args[3], args.Length > 4 ? args[4] : "",
                        args.Length > 5 ? ushort.Parse(args[5]) : (ushort)51211);
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
