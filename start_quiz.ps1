param(
    [int]$Port = 8000,
    [string]$Bind = "0.0.0.0",
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

function Resolve-PythonCommand {
    $venvPython = Join-Path $root ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython) {
        return $venvPython
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        return "py"
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        return "python"
    }

    throw "Python not found. Install Python or create .venv first."
}

function Get-LanIPv4 {
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($route) {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPAddress -ne "127.0.0.1" } |
                Select-Object -ExpandProperty IPAddress -First 1
            if ($ip) { return $ip }
        }
    } catch {
    }

    $fallback = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -ExpandProperty IPAddress -First 1

    if ($fallback) { return $fallback }
    return "127.0.0.1"
}

if (-not (Test-Path -LiteralPath (Join-Path $root "index.html"))) {
    throw "index.html not found. Keep this script in project root."
}

$pythonCommand = Resolve-PythonCommand
$lanIp = Get-LanIPv4
$localUrl = "http://127.0.0.1:$Port/index.html"
$lanUrl = "http://${lanIp}:$Port/index.html"

$existing = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Port $Port is already in use. Assume server is already running." -ForegroundColor Yellow
    Write-Host "Local: $localUrl"
    Write-Host "LAN:   $lanUrl"
    if (-not $NoBrowser) {
        Start-Process $localUrl | Out-Null
    }
    return
}

Write-Host "Starting quiz server..." -ForegroundColor Cyan
Write-Host "Local: $localUrl"
Write-Host "LAN:   $lanUrl"
Write-Host "Stop: press Ctrl + C in this window" -ForegroundColor DarkGray

if (-not $NoBrowser) {
    Start-Process $localUrl | Out-Null
}

if ($pythonCommand -eq "py") {
    & py -3 -m http.server $Port --bind $Bind
} elseif ($pythonCommand -eq "python") {
    & python -m http.server $Port --bind $Bind
} else {
    & $pythonCommand -m http.server $Port --bind $Bind
}
