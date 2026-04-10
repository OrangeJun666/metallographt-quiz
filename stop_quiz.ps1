param(
    [int]$Port = 8000,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$connections = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if (-not $connections) {
    Write-Host "No listening process found on port $Port."
    return
}

$pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
if (-not $pids) {
    Write-Host "No owning process found on port $Port."
    return
}

Write-Host "Found process IDs on port ${Port}: $($pids -join ', ')"

foreach ($pid in $pids) {
    try {
        $proc = Get-Process -Id $pid -ErrorAction Stop
        if ($Force) {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Host "Stopped process $pid ($($proc.ProcessName))"
        } else {
            Stop-Process -Id $pid -ErrorAction Stop
            Write-Host "Stopped process $pid ($($proc.ProcessName))"
        }
    } catch {
        Write-Host "Failed to stop process ${pid}: $($_.Exception.Message)"
    }
}
