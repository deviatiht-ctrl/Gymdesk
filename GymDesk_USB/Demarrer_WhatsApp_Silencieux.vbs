On Error Resume Next
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set wmi = GetObject("winmgmts:\\.\root\cimv2")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
waDir = baseDir & "\whatsapp_service"
If Not fso.FolderExists(waDir) Then
  waDir = baseDir
End If
sh.CurrentDirectory = waDir

' Evite 2 Demarrer_WhatsApp_Silencieux.vbs ap kouri an menm tan
Set scripts = wmi.ExecQuery("Select * from Win32_Process Where Name = 'wscript.exe' AND CommandLine LIKE '%Demarrer_WhatsApp_Silencieux.vbs%'")
If scripts.Count > 1 Then
  WScript.Quit 0
End If

' Mete PATH pou Node.js + Puppeteer Skip Download
envProc = sh.ExpandEnvironmentStrings("%ProgramFiles%\nodejs;%ProgramFiles(x86)%\nodejs;%LOCALAPPDATA%\Programs\nodejs;%APPDATA%\npm;%PATH%")
Set sysEnv = sh.Environment("PROCESS")
sysEnv("PATH") = envProc
sysEnv("PUPPETEER_SKIP_DOWNLOAD") = "true"

' Jwenn node.exe ak npm.cmd
nodeExe = sh.ExpandEnvironmentStrings("%ProgramFiles%\nodejs\node.exe")
If Not fso.FileExists(nodeExe) Then nodeExe = sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%\nodejs\node.exe")
If Not fso.FileExists(nodeExe) Then nodeExe = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\nodejs\node.exe")
If Not fso.FileExists(nodeExe) Then nodeExe = "node.exe"

npmCmd = sh.ExpandEnvironmentStrings("%ProgramFiles%\nodejs\npm.cmd")
If Not fso.FileExists(npmCmd) Then npmCmd = sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%\nodejs\npm.cmd")
If Not fso.FileExists(npmCmd) Then npmCmd = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\nodejs\npm.cmd")
If Not fso.FileExists(npmCmd) Then npmCmd = "npm.cmd"

' Enstale depandans yo an silans si node_modules manke
If fso.FileExists(waDir & "\package.json") And Not fso.FolderExists(waDir & "\node_modules\whatsapp-web.js") Then
  sh.Run "cmd /c """"" & npmCmd & """ install --omit=dev --no-audit --no-fund >> whatsapp.log 2>&1""", 0, True
End If

' Bouk siveyans pemanan an silans: kenbe whatsapp_service/server.js (port 47812) toujou vivan san bloke
Do
  If Not fso.FileExists(waDir & "\server.js") Then
    WScript.Sleep 10000
  Else
    Set procs = wmi.ExecQuery("Select * from Win32_Process Where Name = 'node.exe' AND CommandLine LIKE '%server.js%'")
    If procs.Count = 0 Then
      ' Wote whatsapp.log si li depase 2 MB
      logPath = waDir & "\whatsapp.log"
      If fso.FileExists(logPath) Then
        Set lf = fso.GetFile(logPath)
        If lf.Size > 2097152 Then
          If fso.FileExists(logPath & ".1") Then fso.DeleteFile logPath & ".1", True
          lf.Move logPath & ".1"
        End If
      End If
      sh.Run "cmd /c """"" & nodeExe & """ server.js >> whatsapp.log 2>&1""", 0, True
      WScript.Sleep 3000
    Else
      WScript.Sleep 5000
    End If
  End If
Loop
