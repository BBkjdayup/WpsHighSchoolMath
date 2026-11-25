$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "scripts\uninstall-registration.ps1")

$testId = [Guid]::NewGuid().ToString("N")
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "hsm-uninstall-registration-$testId"
$sourceRoot = Join-Path $testRoot "source"
$uninstallRoot = Join-Path $testRoot "installed-uninstaller"
$startMenuRoot = Join-Path $testRoot "start-menu"
$jsAddonsPath = Join-Path $testRoot "jsaddons"
$registryPath = "HKCU:\Software\WpsHighSchoolMathTests\$testId"
New-Item -ItemType Directory -Path $sourceRoot, $jsAddonsPath -Force | Out-Null

try {
    foreach ($fileName in @("uninstall.ps1", "uninstall-cleanup.ps1", "uninstall-registration.ps1", "addin-maintenance.ps1")) {
        [IO.File]::WriteAllText((Join-Path $sourceRoot $fileName), "# $fileName", (New-Object Text.UTF8Encoding($false)))
    }
    $payload = Join-Path $jsAddonsPath "WpsHighSchoolMath_9.9.9"
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $payload "main.js"), "test", (New-Object Text.UTF8Encoding($false)))

    Set-HsmUninstallRegistryValues -RegistryPath $registryPath -StringValues @{ Contact = "obsolete test contact" } -DwordValues @{}
    $registered = Register-HsmUninstaller `
        -Version "9.9.9" `
        -SourceRoot $sourceRoot `
        -JsAddonsPath $jsAddonsPath `
        -UninstallRoot $uninstallRoot `
        -RegistryPath $registryPath `
        -StartMenuDirectory $startMenuRoot

    if ($registered.Version -ne "9.9.9" -or
        -not (Test-Path -LiteralPath (Join-Path $uninstallRoot "uninstall.ps1")) -or
        -not (Test-Path -LiteralPath $registered.ShortcutPath)) {
        throw "Uninstaller registration did not install all persistent components."
    }
    $entry = Get-ItemProperty -LiteralPath $registryPath
    if ($entry.PSObject.Properties["Contact"] -or $entry.DisplayName -ne "WPS 高中数学工具插件" -or
        $entry.UninstallString -notlike "*uninstall.ps1*" -or
        $entry.QuietUninstallString -notlike "*uninstall.ps1* -Quiet" -or
        $entry.Comments -notlike "*全部功能免费*") {
        throw "Windows installed-app metadata is incomplete."
    }

    $oldScript = Join-Path $uninstallRoot "uninstall.ps1"
    [IO.File]::WriteAllText($oldScript, "previous uninstaller")
    $failed = $false
    try {
        & {
            function Test-HsmUninstallerRegistration { throw "injected Windows registration validation failure" }
            Register-HsmUninstaller -Version "next" -SourceRoot $sourceRoot -JsAddonsPath $jsAddonsPath -UninstallRoot $uninstallRoot -RegistryPath $registryPath -StartMenuDirectory $startMenuRoot
        }
    } catch {
        if ($_.Exception.Message -notlike "*injected Windows*") { throw }
        $failed = $true
    }
    if (-not $failed -or [IO.File]::ReadAllText($oldScript) -ne "previous uninstaller" -or
        (Get-HsmUninstallRegistryValues $registryPath).DisplayVersion -ne "9.9.9") {
        throw "Windows registration failure did not restore the previous registry and uninstall files."
    }

    [void](Unregister-HsmUninstaller -UninstallRoot $uninstallRoot -RegistryPath $registryPath -StartMenuDirectory $startMenuRoot)
    if ((Test-Path -LiteralPath $registryPath) -or (Test-Path -LiteralPath $registered.ShortcutPath)) {
        throw "Uninstaller deregistration left a registry entry or Start-menu shortcut."
    }
    if (-not (Test-Path -LiteralPath $uninstallRoot -PathType Container)) {
        throw "Registration cleanup removed persistent files before the delayed self-cleanup stage."
    }

    $originalLocal = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $testRoot
        $active = (Get-HsmUninstallPaths).Root
        $race = @{ Version = "9.9.9"; SourceRoot = $sourceRoot; JsAddonsPath = $jsAddonsPath
            UninstallRoot = $active; RegistryPath = $registryPath; StartMenuDirectory = $startMenuRoot }
        Copy-Item -LiteralPath (Join-Path $projectRoot "scripts\offline-uninstall-cleanup.ps1") -Destination (Join-Path $sourceRoot "uninstall-cleanup.ps1") -Force
        [void](Register-HsmUninstaller @race)
        $old = Unregister-HsmUninstaller -UninstallRoot $active -RegistryPath $registryPath -StartMenuDirectory $startMenuRoot
        $retired = Move-HsmUninstallRootAside $old.Root
        [void](Register-HsmUninstaller @race)
        & (Join-Path $retired "uninstall-cleanup.ps1") -TargetRoot $retired -ParentProcessId 0
        if ([IO.Directory]::Exists($retired)) { throw "Retired directory was not cleaned." }
        [void](Test-HsmUninstallerRegistration -Version "9.9.9" -UninstallRoot $active -RegistryPath $registryPath -StartMenuDirectory $startMenuRoot)
        $refused = $false
        try { & (Join-Path $active "uninstall-cleanup.ps1") -TargetRoot $active -ParentProcessId 0 }
        catch { $refused = $_.Exception.Message -match "unexpected uninstall directory" }
        if (-not $refused) { throw "Delayed cleanup accepted the active uninstaller." }
    } finally { $env:LOCALAPPDATA = $originalLocal }
    Write-Output "Windows uninstall registration, rollback and rapid reinstall tests passed"
} finally {
    if (Test-Path -LiteralPath $registryPath) {
        Remove-Item -LiteralPath $registryPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
