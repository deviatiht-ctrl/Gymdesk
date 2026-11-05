Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\whatsapp_service"
WshShell.Run "cmd /c LANCER_WHATSAPP.bat", 0, False
