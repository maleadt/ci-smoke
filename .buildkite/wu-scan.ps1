# What Microsoft Update offers this guest right now (search only, nothing installed).
# The image disables Windows Update; this disposable guest re-enables the services.
$ErrorActionPreference = 'Stop'
& sc.exe config wuauserv start= demand
& sc.exe start wuauserv
Start-Sleep -Seconds 5
Get-Service wuauserv, bits | Format-Table -AutoSize Name, Status, StartType | Out-String
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searcher.ServerSelection = 3   # ssOthers: the service below, not the WSUS policy
$searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'   # Microsoft Update
$result = $searcher.Search("IsInstalled=0 and Type='Software'")
"Offered now: $($result.Updates.Count) updates"
foreach ($u in $result.Updates) { "  $($u.Title)" }
