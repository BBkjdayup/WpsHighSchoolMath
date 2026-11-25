$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "scripts\addin-maintenance.ps1")
Assert-HsmWpsClosed -Processes @()
foreach ($handle in @(0, 12345)) {
    $blocked = $false
    try { Assert-HsmWpsClosed -Processes @([pscustomobject]@{ ProcessName = "wpp"; MainWindowHandle = $handle; Saved = 0 }) }
    catch { $blocked = $_.Exception.Message -match "保存文档" }
    if (-not $blocked) { throw "Maintenance allowed a live WPS document session with handle $handle." }
}
foreach ($file in @("offline-install.ps1", "offline-uninstall.ps1")) {
    $source = [IO.File]::ReadAllText((Join-Path $projectRoot ("scripts\" + $file)))
    if ($source -notmatch 'Assert-HsmWpsClosed' -or $source -match 'Stop-WpsBackgroundHosts') { throw "Missing WPS protection in $file" }
}
Write-Output "Visible and windowless WPS processes are protected."
