On Error Resume Next
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = dir
exe = dir & "\access_agent.exe"

' Evite 2 wscript.exe k ap tournen an menm tan
Set scripts = wmi.ExecQuery("Select * from Win32_Process Where Name = 'wscript.exe' AND CommandLine LIKE '%Demarrer_Agent_Silencieux.vbs%'")
If scripts.Count > 1 Then
  WScript.Quit 0
End If

' Bouk siveyans pèmanan an silans: kenbe access_agent.exe toujou limen nan background
Do
  Set procs = wmi.ExecQuery("Select * from Win32_Process Where Name = 'access_agent.exe'")
  If procs.Count = 0 Then
    If fso.FileExists(exe) Then
      sh.Run """" & exe & """", 0, True
    End If
  End If
  WScript.Sleep 4000
Loop
