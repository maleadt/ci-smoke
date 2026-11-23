# What Windows Update offers this guest right now (search only, nothing installed).
$ErrorActionPreference = 'Stop'
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
"Service: $((New-Object -ComObject Microsoft.Update.ServiceManager).Services | Where-Object IsDefaultAUService | ForEach-Object Name)"
foreach ($criteria in "IsInstalled=0 and Type='Software'", "IsInstalled=0 and IsHidden=1") {
    $result = $searcher.Search($criteria)
    "${criteria}: $($result.Updates.Count) updates"
    foreach ($u in $result.Updates) { "  $($u.Title)" }
}
