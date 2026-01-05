If WScript.Arguments.Count = 0 Then WScript.Quit

Dim WinScriptHost
Set WinScriptHost = CreateObject("WScript.Shell")

Dim args, i
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next

WinScriptHost.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File " & args, 0, False

Set WinScriptHost = Nothing