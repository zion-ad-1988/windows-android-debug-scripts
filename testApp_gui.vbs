Option Explicit

Dim fso, sh, baseDir, scriptPath, psExe, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(baseDir, "testApp_gui.ps1")
psExe = sh.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")

sh.CurrentDirectory = baseDir
sh.Environment("PROCESS")("PATH") = fso.BuildPath(baseDir, "scrcpy") & ";" & sh.Environment("PROCESS")("PATH")

cmd = """" & psExe & """ -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptPath & """"
sh.Run cmd, 0, False