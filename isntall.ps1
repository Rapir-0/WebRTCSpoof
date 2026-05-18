# install.ps1 - launcher with UAC and UTF-8 download

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
$OutputEncoding           = [System.Text.UTF8Encoding]::new()
try { chcp 65001 | Out-Null } catch {}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptUrl = 'https://raw.githubusercontent.com/Rapir-0/WebRTCSpoof/main/webrtc.ps1'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Requesting admin rights...' -ForegroundColor Yellow

    # Качаем скрипт здесь, под обычным юзером, как UTF-8 байты
    $bytes  = (Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing).Content
    if ($bytes -is [string]) {
        # PS 5.1 уже превратил в строку — перекодируем обратно
        $raw    = [System.Text.Encoding]::GetEncoding(1251).GetBytes($bytes)
        $script = [System.Text.Encoding]::UTF8.GetString($raw)
    } else {
        $script = [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    # Сохраняем во временный файл
    $tmp = "$env:TEMP\webrtc_spoof_$(Get-Random).ps1"
    [System.IO.File]::WriteAllText($tmp, $script, [System.Text.UTF8Encoding]::new($true))

    # Запускаем от админа через файл (не через -Command, чтобы кодировка не сломалась)
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-NoExit',
        '-ExecutionPolicy','Bypass',
        '-File', $tmp
    )
    exit
}

# Уже от админа — скачиваем и выполняем как UTF-8
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$script = $wc.DownloadString($scriptUrl)
Invoke-Expression $script
