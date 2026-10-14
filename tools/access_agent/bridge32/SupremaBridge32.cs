// Pon 32-bit pou SDK Suprema BioMini (UFScanner.dll / UFMatcher.dll x86, __stdcall).
// Agent 64-bit la lanse pwogram sa a yon fwa pa kòmand (stdin pa janm rive
// lè Dart lanse yon pwosesis .NET sou Windows):
//   suprema_bridge32.exe <dllDir> status              -> ok <count> <scannerId>
//   suprema_bridge32.exe <dllDir> capture <timeoutMs> -> ok <templateB64> <quality> | err <code> <msg>
//   suprema_bridge32.exe <dllDir> verify <b64a> <b64b>-> ok 1|0
//   suprema_bridge32.exe <dllDir> identify <probe> <file>
//     <file>: fichye tèks, yon template base64 pa liy           -> ok <index ou -1>
//   san kòmand: mòd entèaktif stdin/stdout (tès manyèl), yon liy pa demann, "ready" an premye.
// Separatè a se TAB. Bati: csc /platform:x86 /target:exe SupremaBridge32.cs
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

static class Native
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetDllDirectory(string path);

    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_Init();
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_Update();
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_GetScannerNumber(out int count);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_GetScannerHandle(int index, out IntPtr handle);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_GetScannerID(IntPtr handle, byte[] id);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_SetParameter(IntPtr handle, int param, ref int value);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_SetTemplateType(IntPtr handle, int type);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_ClearCaptureImageBuffer(IntPtr handle);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_CaptureSingleImage(IntPtr handle);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_Extract(IntPtr handle, byte[] template, out int size, out int quality);
    [DllImport("UFScanner.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFS_GetErrorString(int code, byte[] message);

    [DllImport("UFMatcher.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFM_Create(out IntPtr matcher);
    [DllImport("UFMatcher.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFM_SetTemplateType(IntPtr matcher, int type);
    [DllImport("UFMatcher.dll", CallingConvention = CallingConvention.StdCall)] public static extern int UFM_Verify(IntPtr matcher, byte[] a, int aSize, byte[] b, int bSize, out int verified);
}

static class Program
{
    const int Ok = 0, ParamTimeout = 201, Iso19794_2 = 2002, SupremaNative = 2001, MaxTemplate = 1024;
    static IntPtr matcher = IntPtr.Zero;
    static bool matcherReady = false;

    static string Clean(string s) { return (s ?? "").Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ').Trim(); }

    static string Describe(int code)
    {
        try
        {
            var buf = new byte[256];
            Native.UFS_GetErrorString(code, buf);
            var s = Encoding.Default.GetString(buf).TrimEnd('\0').Trim();
            return s.Length == 0 ? "code " + code : s + " (code " + code + ")";
        }
        catch { return "code " + code; }
    }

    static string Status()
    {
        Native.UFS_Update();
        int count;
        Native.UFS_GetScannerNumber(out count);
        var id = "";
        IntPtr h;
        if (count > 0 && Native.UFS_GetScannerHandle(0, out h) == Ok)
        {
            var buf = new byte[128];
            Native.UFS_GetScannerID(h, buf);
            id = Encoding.ASCII.GetString(buf).TrimEnd('\0').Trim();
        }
        return "ok\t" + count + "\t" + Clean(id);
    }

    static string Capture(int timeoutMs, int tplType)
    {
        IntPtr h;
        var rc = Native.UFS_GetScannerHandle(0, out h);
        if (rc != Ok) return "err\tno_reader\tLecteur non détecté (" + Clean(Describe(rc)) + ").";
        var timeout = timeoutMs;
        Native.UFS_SetParameter(h, ParamTimeout, ref timeout);
        // tplType: 2002 = ISO 19794-2 (defo), 2001 = fòma natif Suprema (384B,
        // sa tèminal BioEntry W2 a konnen pou enroll sou li).
        try { Native.UFS_SetTemplateType(h, tplType); } catch (EntryPointNotFoundException) { }
        Native.UFS_ClearCaptureImageBuffer(h);
        rc = Native.UFS_CaptureSingleImage(h);
        if (rc != Ok) return "err\tcapture_failed\tAucun doigt détecté ou capture échouée: " + Clean(Describe(rc));
        var tpl = new byte[MaxTemplate];
        int size, quality;
        rc = Native.UFS_Extract(h, tpl, out size, out quality);
        if (rc != Ok || size <= 0 || size > MaxTemplate) return "err\textract_failed\tExtraction impossible: " + Clean(Describe(rc));
        var bytes = new byte[size];
        Array.Copy(tpl, bytes, size);
        return "ok\t" + Convert.ToBase64String(bytes) + "\t" + quality;
    }

    static bool Verify(byte[] a, byte[] b)
    {
        if (a.Length == 0 || b.Length == 0) return false;
        int verified;
        return Native.UFM_Verify(matcher, a, a.Length, b, b.Length, out verified) == Ok && verified != 0;
    }

    static byte[] B64(string s) { try { return Convert.FromBase64String(s.Trim()); } catch { return new byte[0]; } }

    static int Main(string[] args)
    {
        var dir = args.Length > 0 ? args[0] : AppDomain.CurrentDomain.BaseDirectory;
        var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
        var stdin = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
        try
        {
            Native.SetDllDirectory(dir);
            var rc = Native.UFS_Init();
            if (rc != Ok) { stdout.WriteLine("err\tsdk_init\tUFS_Init: " + Clean(Describe(rc))); return 1; }
            // UFM_Create depann de lektè a: si li echwe, status/capture rete
            // disponib; verify/identify ap rapòte erè a lè sa nesesè.
            matcherReady = Native.UFM_Create(out matcher) == Ok;
            if (matcherReady)
            {
                try { Native.UFM_SetTemplateType(matcher, Iso19794_2); } catch (EntryPointNotFoundException) { }
            }
        }
        catch (Exception e)
        {
            stdout.WriteLine("err\tsdk_missing\t" + Clean(e.Message));
            return 1;
        }
        if (args.Length > 1)
        {
            var cmd = new string[args.Length - 1];
            Array.Copy(args, 1, cmd, 0, cmd.Length);
            stdout.WriteLine(Run(cmd));
            return 0;
        }
        stdout.WriteLine("ready");

        string line;
        while ((line = stdin.ReadLine()) != null)
        {
            var p = line.Split('\t');
            if (p[0] == "quit") return 0;
            stdout.WriteLine(Run(p));
        }
        return 0;
    }

    static string Run(string[] p)
    {
        try
        {
            switch (p[0])
            {
                case "status": return Status();
                case "capture": return Capture(
                    p.Length > 1 ? int.Parse(p[1]) : 10000,
                    p.Length > 2 ? int.Parse(p[2]) : Iso19794_2);
                case "verify":
                    if (!matcherReady) return "err\tmatcher_init\tUFM_Create a échoué (lecteur connecté ?)";
                    return "ok\t" + (p.Length > 2 && Verify(B64(p[1]), B64(p[2])) ? "1" : "0");
                case "identify":
                    if (!matcherReady) return "err\tmatcher_init\tUFM_Create a échoué (lecteur connecté ?)";
                    var probe = p.Length > 1 ? B64(p[1]) : new byte[0];
                    var candidates = new string[0];
                    if (p.Length > 2 && p[2].Length > 0)
                        candidates = File.Exists(p[2]) ? File.ReadAllLines(p[2]) : p[2].Split(',');
                    var found = -1;
                    for (var i = 0; i < candidates.Length && found < 0; i++)
                        if (Verify(probe, B64(candidates[i]))) found = i;
                    return "ok\t" + found;
                default: return "err\tunknown_command\t" + Clean(p[0]);
            }
        }
        catch (Exception e) { return "err\tsdk_error\t" + Clean(e.Message); }
    }
}
