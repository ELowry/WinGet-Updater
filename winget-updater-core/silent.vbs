If WScript.Arguments.Count = 0 Then WScript.Quit

Dim WinScriptHost
Set WinScriptHost = CreateObject("WScript.Shell")

WinScriptHost.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """", 0, False

Set WinScriptHost = Nothing