# What Microsoft Update offers this guest right now (search only, nothing installed).
# The image disables Windows Update; this disposable guest re-enables the services.
$ErrorActionPreference = 'Stop'
foreach ($svc in 'bits', 'wuauserv') {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name Start -Value 3
    Start-Service $svc
}
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searcher.ServerSelection = 3   # ssOthers: the service below, not the WSUS policy
$searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'   # Microsoft Update
$result = $searcher.Search("IsInstalled=0 and Type='Software'")
"Offered now: $($result.Updates.Count) updates"
foreach ($u in $result.Updates) { "  $($u.Title)" }
