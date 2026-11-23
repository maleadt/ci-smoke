# Checks of a Windows worker image without Docker (sba tb/remove-docker-windows).
# Usage: powershell -NoProfile -File image-checks.ps1 write|read
param([string]$mode)
$ErrorActionPreference = 'Stop'
$failures = @()

Write-Output '--- OS and licence'
$os = Get-CimInstance Win32_OperatingSystem
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
"$($os.Caption) $($os.Version).$ubr, installed $($os.InstallDate.ToString('u'))"
Get-HotFix | Sort-Object InstalledOn | Select-Object -Last 3 | Format-Table -AutoSize HotFixID, Description, InstalledOn | Out-String -Width 200
cscript //nologo C:\Windows\System32\slmgr.vbs /dli
cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
$timeout = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control -ErrorAction SilentlyContinue).ServicesPipeTimeout
"ServicesPipeTimeout: $(if ($null -eq $timeout) { 'unset (default)' } else { $timeout })"

Write-Output '--- Docker and Windows Containers'
$commands = @(Get-Command docker, dockerd -ErrorAction SilentlyContinue)
$service = Get-Service docker -ErrorAction SilentlyContinue
$feature = Get-WindowsFeature Containers
"docker/dockerd on PATH: $(if ($commands) { $commands.Source -join ', ' } else { 'no' })"
"docker service: $(if ($service) { $service.Status } else { 'absent' })"
"Containers feature: $($feature.InstallState)"
foreach ($path in 'C:\Program Files\docker', 'C:\ProgramData\docker', 'Z:\docker-data') {
    "${path}: $(if (Test-Path $path) { 'present' } else { 'absent' })"
    if (Test-Path $path) { $failures += "$path present" }
}
if ($commands) { $failures += 'docker on PATH' }
if ($service) { $failures += 'docker service' }
if ($feature.Installed) { $failures += 'Containers feature installed' }
Get-NetAdapter | Format-Table -AutoSize Name, InterfaceDescription, Status | Out-String -Width 200
Get-NetIPAddress -AddressFamily IPv4 | Format-Table -AutoSize InterfaceAlias, IPAddress, PrefixOrigin, AddressState | Out-String -Width 200

Write-Output '--- Cache volume'
$partition = Get-Partition -DriveLetter Z
"Z: partition access paths: $($partition.AccessPaths -join ', ')"
Get-Volume -DriveLetter Z | Format-Table -AutoSize FileSystemLabel, FileSystem, SizeRemaining, Size | Out-String -Width 200
if (-not ($partition.AccessPaths -contains 'C:\cache\')) { $failures += 'C:\cache is not a mount point of Z:' }
Get-ChildItem Z:\ | Format-Table -AutoSize Mode, LastWriteTime, Name | Out-String -Width 200
$marker = 'smoke-marker.txt'
if ($mode -eq 'write') {
    "$env:BUILDKITE_BUILD_NUMBER $env:BUILDKITE_JOB_ID" | Set-Content "C:\cache\$marker"
    "wrote C:\cache\$marker, read back through Z:: $(Get-Content "Z:\$marker")"
} else {
    $content = Get-Content "Z:\$marker" -ErrorAction SilentlyContinue
    "read Z:\$marker from a fresh OS overlay: $content"
    if ($content -notlike "$env:BUILDKITE_BUILD_NUMBER *") { $failures += 'marker from the earlier job of this build missing' }
}
Get-PSDrive C | Format-Table -AutoSize Name, Used, Free | Out-String -Width 200

if ($failures) {
    Write-Output "+++ FAILED: $($failures -join '; ')"
    exit 1
}
Write-Output 'All image checks passed'
