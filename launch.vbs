Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & dir & "\reboot-reminder.ps1"""
Set sh = CreateObject("Wscript.Shell")
sh.Run cmd, 0, False
