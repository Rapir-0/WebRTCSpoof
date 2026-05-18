# webrtc.ps1 — WebRTC IP Spoofer by cle0man
# https://t.me/cle0man
# Запускать от администратора

param(
    [string]$AdapterName = "Ethernet"
)

# --- Принудительно ставим UTF-8 для консоли ---
$OutputEncoding           = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
try { chcp 65001 | Out-Null } catch {}

# --- Баннер ---
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │                                             │" -ForegroundColor DarkCyan
Write-Host "  │   " -ForegroundColor DarkCyan -NoNewline
Write-Host "██╗    ██╗███████╗██████╗ ██████╗ ████████╗" -ForegroundColor Cyan -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  │   " -ForegroundColor DarkCyan -NoNewline
Write-Host "██║    ██║██╔════╝██╔══██╗╚════██╗╚══██╔══╝" -ForegroundColor Cyan -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  │   " -ForegroundColor DarkCyan -NoNewline
Write-Host "██║ █╗ ██║█████╗  ██████╔╝ █████╔╝   ██║   " -ForegroundColor Cyan -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  │   " -ForegroundColor DarkCyan -NoNewline
Write-Host "██║███╗██║██╔══╝  ██╔══██╗ ╚═══██╗   ██║   " -ForegroundColor Cyan -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  │   " -ForegroundColor DarkCyan -NoNewline
Write-Host "╚███╔███╔╝███████╗██████╔╝██████╔╝   ██║   " -ForegroundColor Cyan -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  │   " -ForegroundColor DarkCyan -NoNewline
Write-Host " ╚══╝╚══╝ ╚══════╝╚═════╝ ╚═════╝    ╚═╝   " -ForegroundColor Cyan -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  │                                             │" -ForegroundColor DarkCyan
Write-Host "  │           " -ForegroundColor DarkCyan -NoNewline
Write-Host "WebRTC Spoofer by " -ForegroundColor Gray -NoNewline
Write-Host "cle0man" -ForegroundColor White -NoNewline
Write-Host "             │" -ForegroundColor DarkCyan
Write-Host "  │      " -ForegroundColor DarkCyan -NoNewline
Write-Host "Telegram: " -ForegroundColor Gray -NoNewline
Write-Host "https://t.me/cle0man" -ForegroundColor Yellow -NoNewline
Write-Host "       │" -ForegroundColor DarkCyan
Write-Host "  │                                             │" -ForegroundColor DarkCyan
Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor DarkCyan
Write-Host ""
Start-Sleep -Milliseconds 600

# --- Проверка админских прав ---
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Скрипт нужно запускать от администратора!" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

# --- Находим адаптер ---
$adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
if (-not $adapter) {
    Write-Host "Адаптер '$AdapterName' не найден. Доступные:" -ForegroundColor Red
    Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription | Format-Table
    Read-Host "Нажмите Enter для выхода"
    exit 1
}
$ifIndex = $adapter.ifIndex

# --- Отключаем IPv6 на всех адаптерах (утечка WebRTC через IPv6) ---
Write-Host "Отключаю IPv6..." -ForegroundColor Cyan
Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue |
    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
Write-Host "  IPv6 отключён на всех адаптерах." -ForegroundColor Green


# ============================================================
# --- СБРОС В DHCP (восстанавливаем интернет после прошлого запуска) ---
# ============================================================
Write-Host "Сбрасываю адаптер в исходное состояние (DHCP)..." -ForegroundColor Cyan

# 1) Удаляем все статические IPv4 адреса
Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.PrefixOrigin -eq 'Manual' } |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# 2) Удаляем дефолтные маршруты (могли остаться от прошлой подмены)
Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# 3) Включаем DHCP для IP и сбрасываем DNS
netsh interface ipv4 set address name="$AdapterName" source=dhcp 2>&1 | Out-Null
netsh interface ipv4 set dnsservers name="$AdapterName" source=dhcp 2>&1 | Out-Null

# 4) Обновляем аренду
ipconfig /release "$AdapterName" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
ipconfig /renew "$AdapterName" 2>&1 | Out-Null

Write-Host "  Жду восстановления интернета..." -ForegroundColor Gray

# 5) Ждём пока появится валидный шлюз и интернет (до 20 секунд)
$gotInternet = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 1
    $cfg = Get-NetIPConfiguration -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
    $gw  = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop
    if ($gw) {
        $ping = Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($ping) {
            Write-Host "  Интернет восстановлен (Gateway: $gw, попытка $i)" -ForegroundColor Green
            $gotInternet = $true
            break
        }
    }
    Write-Host "  Попытка $i/20..." -ForegroundColor DarkGray
}

if (-not $gotInternet) {
    Write-Host "Не удалось восстановить интернет за 20 секунд." -ForegroundColor Red
    Write-Host "Проверьте подключение и попробуйте ещё раз." -ForegroundColor Yellow
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

# --- Читаем текущие настройки (теперь точно от DHCP) ---
Write-Host "Читаю текущие настройки адаптера..." -ForegroundColor Cyan

$config = Get-NetIPConfiguration -InterfaceIndex $ifIndex
$currentGateway = ($config.IPv4DefaultGateway | Select-Object -First 1).NextHop
$currentDNS = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).ServerAddresses

if (-not $currentGateway) {
    Write-Host "Не удалось определить текущий Gateway. Адаптер подключён?" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

Write-Host "  Текущий Gateway: $currentGateway" -ForegroundColor Gray
Write-Host "  Текущий DNS:     $($currentDNS -join ', ')" -ForegroundColor Gray

# --- Бэкап ---
$backupPath = "$env:TEMP\adapter_backup_$AdapterName.json"
@{
    AdapterName = $AdapterName
    Gateway     = $currentGateway
    DNS         = $currentDNS
    Date        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Бэкап настроек: $backupPath" -ForegroundColor DarkGray

# --- Узнаём публичный IP ---
Write-Host "Получаю публичный IP..." -ForegroundColor Cyan

$publicIP = $null
$services = @(
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
    "https://ipinfo.io/ip"
)

foreach ($url in $services) {
    try {
        $result = (Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing).Content.Trim()
        if ($result -match '^\d{1,3}(\.\d{1,3}){3}$') {
            $publicIP = $result
            Write-Host "  Публичный IP: $publicIP (через $url)" -ForegroundColor Green
            break
        }
    } catch {
        Write-Host "  $url — не отвечает, пробую следующий..." -ForegroundColor DarkYellow
    }
}

if (-not $publicIP) {
    Write-Host "Не удалось получить публичный IP." -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

# --- Переключаем в Manual режим перед назначением статики ---
Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# --- Применяем настройки через netsh (он игнорирует subnet-проверку) ---
Write-Host "Применяю новые настройки:" -ForegroundColor Cyan
Write-Host "  IP:      $publicIP / 255.0.0.0" -ForegroundColor White
Write-Host "  Gateway: $currentGateway" -ForegroundColor White
Write-Host "  DNS:     $($currentDNS -join ', ')" -ForegroundColor White

# Прописываем IP + маску + шлюз через netsh
$netshOutput = netsh interface ipv4 set address name="$AdapterName" static $publicIP 255.0.0.0 $currentGateway 2>&1

if ($LASTEXITCODE -ne 0 -or $netshOutput -match "(?i)(error|fail|denied|invalid)") {
    Write-Host "netsh вернул проблему:" -ForegroundColor Yellow
    Write-Host $netshOutput
}

# Прописываем DNS
$primaryDNS = $currentDNS | Select-Object -First 1
netsh interface ipv4 set dnsservers name="$AdapterName" static $primaryDNS primary validate=no | Out-Null

# Если есть второй DNS — добавим
if ($currentDNS.Count -gt 1) {
    $secondaryDNS = $currentDNS[1]
    netsh interface ipv4 add dnsservers name="$AdapterName" $secondaryDNS index=2 validate=no | Out-Null
}

Start-Sleep -Milliseconds 500

# --- Проверяем результат ---
$newConfig = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
$assigned = $newConfig | Where-Object { $_.IPAddress -eq $publicIP }

if ($assigned) {
    Write-Host "`nГотово! IP $publicIP назначен. WebRTC должен показывать его." -ForegroundColor Green
} else {
    Write-Host "`nЧто-то пошло не так, IP не назначился. Текущее состояние:" -ForegroundColor Red
    $newConfig | Format-Table IPAddress, PrefixLength, PrefixOrigin
}

Write-Host "`nИтоговая конфигурация адаптера:" -ForegroundColor Cyan
ipconfig | Select-String -Pattern "Ethernet|IPv4|Subnet|Gateway|DNS" -Context 0,0

# ============================================================
# --- Chrome: ставим флаг Anonymize local IPs = Disabled ---
# ============================================================
Write-Host "`nНастраиваю Chrome (флаг WebRTC mDNS = Disabled)..." -ForegroundColor Cyan

# Запоминаем, был ли Chrome запущен, чтобы заново открыть
$chromeWasRunning = $false
$chromeExe = $null

$chromeProcesses = Get-Process chrome -ErrorAction SilentlyContinue
if ($chromeProcesses) {
    $chromeWasRunning = $true
    $chromeExe = ($chromeProcesses | Select-Object -First 1).Path
    Write-Host "  Закрываю Chrome..." -ForegroundColor Gray
    $chromeProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Если Chrome не был запущен — пытаемся найти exe в стандартных местах
if (-not $chromeExe) {
    $chromeCandidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $chromeExe = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"

if (-not (Test-Path $localStatePath)) {
    Write-Host "  Local State не найден ($localStatePath). Пропускаю настройку флага." -ForegroundColor Yellow
} else {
    try {
        $json = Get-Content $localStatePath -Raw -Encoding UTF8 | ConvertFrom-Json

        if (-not $json.browser) {
            $json | Add-Member -NotePropertyName "browser" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not $json.browser.enabled_labs_experiments) {
            $json.browser | Add-Member -NotePropertyName "enabled_labs_experiments" -NotePropertyValue @() -Force
        }

        # Убираем любые варианты этого флага (если уже стояли)
        $filtered = @($json.browser.enabled_labs_experiments | Where-Object { $_ -notmatch '^enable-webrtc-hide-local-ips-with-mdns' })

        # Добавляем Disabled (@2)
        $filtered += "enable-webrtc-hide-local-ips-with-mdns@2"
        $json.browser.enabled_labs_experiments = $filtered

        # Сохраняем без BOM (Chrome не любит BOM)
        $jsonText = $json | ConvertTo-Json -Depth 100 -Compress
        [System.IO.File]::WriteAllText($localStatePath, $jsonText, [System.Text.UTF8Encoding]::new($false))

        Write-Host "  Флаг Anonymize local IPs = Disabled выставлен." -ForegroundColor Green
    } catch {
        Write-Host "  Ошибка при правке Local State: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Запускаем Chrome обратно, если он был открыт
if ($chromeWasRunning -and $chromeExe -and (Test-Path $chromeExe)) {
    Write-Host "  Запускаю Chrome обратно..." -ForegroundColor Gray
    Start-Process -FilePath $chromeExe
} elseif ($chromeWasRunning) {
    Write-Host "  Chrome был запущен, но exe не найден — запустите вручную." -ForegroundColor Yellow
}

Read-Host "`nНажмите Enter для выхода"
