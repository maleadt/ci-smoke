# Checks of a Windows worker image without Docker (sba tb/remove-docker-windows,
# tb/windows-server-2025).
# Usage: powershell -NoProfile -File image-checks.ps1 write|read
param([string]$mode)
$ErrorActionPreference = 'Stop'
$failures = @()

Write-Output '--- OS and licence'
$os = Get-CimInstance Win32_OperatingSystem
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
"$($os.Caption) $($os.Version).$ubr, installed $($os.InstallDate.ToString('u'))"
Get-HotFix | Sort-Object InstalledOn | Select-Object -Last 3 | Format-Table -AutoSize HotFixID, Description, InstalledOn | Out-String -Width 200
if (Test-Path C:\Windows\Temp\win-updates.log) {
    Write-Output 'Windows Update log of the base build (C:\Windows\Temp\win-updates.log):'
    Get-Content C:\Windows\Temp\win-updates.log | Select-String -Pattern 'Adding:|Cycle|Done|Stopping|Error|Restart Required|updates? (found|to)' | Select-Object -Last 40 | ForEach-Object Line
}
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

Write-Output '--- Visual C++ redistributables'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object DisplayName -like 'Microsoft Visual C++*' | Sort-Object DisplayName | ForEach-Object DisplayName

Write-Output '--- Defender'
Get-WindowsFeature Windows-Defender | Format-Table -AutoSize Name, InstallState | Out-String -Width 200

Write-Output '--- OpenSSH'
$sshDir = 'C:\Windows\System32\OpenSSH'
cmd /c "`"$sshDir\ssh.exe`" -V 2>&1"
foreach ($svc in 'sshd', 'ssh-agent') {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    "${svc}: $(if ($s) { "$($s.Status), $($s.StartType)" } else { 'absent' })"
}
if (-not (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue)) { $failures += 'sshd not listening on 22' }
$rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
"firewall rule OpenSSH-Server-In-TCP: $(if ($rule) { "enabled $($rule.Enabled), profile $($rule.Profile)" } else { 'absent' }); network category $((Get-NetConnectionProfile).NetworkCategory -join ', ')"
if (-not $rule -or $rule.Enabled -ne 'True') { $failures += 'sshd firewall rule' }
$keyscan = cmd /c "`"$sshDir\ssh-keyscan.exe`" github.com 2>&1"
$keyscan | Where-Object { $_ -match '^github\.com ' } | ForEach-Object { "keyscan: $($_.Substring(0, [Math]::Min(70, $_.Length)))..." }
if (-not ($keyscan -match '^github\.com ssh-ed25519 ')) { $failures += 'ssh-keyscan github.com'; $keyscan }
$tmp = Join-Path $env:TEMP ('sshtest-' + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
cmd /c "`"$sshDir\ssh-keygen.exe`" -q -t ed25519 -N `"`" -f `"$tmp\id`""
# A throwaway key: GitHub must refuse it after key exchange and authentication negotiated.
$github = cmd /c "`"$sshDir\ssh.exe`" -T -i `"$tmp\id`" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=`"$tmp\known_hosts`" git@github.com 2>&1"
"ssh -T git@github.com: $github"
if (-not ($github -match 'Permission denied \(publickey\)')) { $failures += 'ssh to github.com' }
Start-Service ssh-agent
cmd /c "`"$sshDir\ssh-add.exe`" `"$tmp\id`" 2>&1"
$listed = cmd /c "`"$sshDir\ssh-add.exe`" -l 2>&1"
"ssh-add -l: $listed"
if (-not ($listed -match 'ED25519')) { $failures += 'ssh-agent' }
cmd /c "`"$sshDir\ssh-add.exe`" -D 2>&1" | Out-Null
Stop-Service ssh-agent

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
