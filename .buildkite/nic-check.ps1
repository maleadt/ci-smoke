# Network of a Windows KVM guest at the job's vCPU count: how long the launcher waited for
# DHCP and DNS, the NIC driver and its receive queues, and a sustained download.
$ErrorActionPreference = 'Stop'
$os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
"Windows build $($os.CurrentBuildNumber).$($os.UBR), vCPUs $((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)"
Get-NetAdapter | Format-Table -AutoSize Name, InterfaceDescription, DriverVersion, LinkSpeed, Status | Out-String -Width 200
Get-NetAdapterRss | Format-List Name, Enabled, NumberOfReceiveQueues, MaxProcessors, Profile | Out-String -Width 200
$log = 'C:\buildkite-agent\run-buildkite-job-launcher.log'
if (Test-Path $log) { 'Launcher log:'; Get-Content $log | Select-Object -Last 15 }
$url = 'https://github.com/JuliaCI/rootfs-images/releases/download/v8.14/package_windows.x86_64.tar.gz'
$out = Join-Path $env:TEMP 'nic-download.bin'
foreach ($i in 1..2) {
    $t = Measure-Command { & curl.exe -sSfL -o $out $url }
    if ($LASTEXITCODE -ne 0) { throw "download $i failed: curl exit code $LASTEXITCODE" }
    $mb = (Get-Item $out).Length / 1MB
    "download ${i}: $([Math]::Round($mb)) MiB in $([Math]::Round($t.TotalSeconds, 1)) s = $([Math]::Round($mb / $t.TotalSeconds, 1)) MiB/s"
    Remove-Item $out
}
$t = Measure-Command { & git clone -q --filter=blob:none https://github.com/JuliaLang/julia.git (Join-Path $env:TEMP 'nic-julia') }
"git clone --filter=blob:none julia: $([Math]::Round($t.TotalSeconds, 1)) s, exit code $LASTEXITCODE"
Get-NetAdapterStatistics | Format-List Name, ReceivedBytes, ReceivedDiscardedPackets, ReceivedPacketErrors, OutboundDiscardedPackets, OutboundPacketErrors | Out-String -Width 200
