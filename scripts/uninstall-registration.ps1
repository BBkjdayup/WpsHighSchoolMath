$script:HsmUninstallProductId = "WpsHighSchoolMath"
$script:HsmUninstallDisplayName = "WPS 高中数学工具插件"
. (Join-Path $PSScriptRoot "addin-maintenance.ps1")

function Invoke-HsmMaintenance {
    param([Parameter(Mandatory = $true)][scriptblock]$Operation)

    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = New-Object Threading.Mutex($false, "Global\WpsHighSchoolMath-Maintenance-$sid")
    $ownsLock = $false
    try {
        try { $ownsLock = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsLock = $true }
        if (-not $ownsLock) { throw "Another installation or removal is in progress. Please retry when it finishes." }
        & $Operation
    } finally {
        if ($ownsLock) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-HsmUninstallPaths {
    param(
        [string]$UninstallRoot,
        [string]$RegistryPath,
        [string]$StartMenuDirectory
    )

    if (-not $UninstallRoot) {
        # Older cleanup processes can still delete the original fixed directory.
        $UninstallRoot = Join-Path $env:LOCALAPPDATA "Programs\WpsHighSchoolMath-Uninstaller"
    }
    if (-not $RegistryPath) {
        $RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WpsHighSchoolMath"
    }
    if (-not $StartMenuDirectory) {
        $StartMenuDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\高中数学插件"
    }
    return [pscustomobject][ordered]@{
        Root = [IO.Path]::GetFullPath($UninstallRoot)
        ScriptPath = Join-Path $UninstallRoot "uninstall.ps1"
        CleanupScriptPath = Join-Path $UninstallRoot "uninstall-cleanup.ps1"
        RegistrationScriptPath = Join-Path $UninstallRoot "uninstall-registration.ps1"
        MaintenanceScriptPath = Join-Path $UninstallRoot "addin-maintenance.ps1"
        RegistryPath = $RegistryPath
        StartMenuDirectory = [IO.Path]::GetFullPath($StartMenuDirectory)
        ShortcutPath = Join-Path $StartMenuDirectory "卸载高中数学插件.cmd"
    }
}

function Move-HsmUninstallRootAside {
    param([string]$Root)
    $active = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\WpsHighSchoolMath-Uninstaller"))
    if ($active -ne [IO.Path]::GetFullPath($Root) -or
        ((Get-Item -LiteralPath $active -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected uninstall directory: $Root"
    }
    $retired = Join-Path ([IO.Path]::GetDirectoryName($active)) ("WpsHighSchoolMath-Uninstalling-" + [Guid]::NewGuid().ToString("N"))
    [IO.Directory]::Move($active, $retired)
    return $retired
}

function Get-HsmRegistrySubKeyPath {
    param([Parameter(Mandatory = $true)][string]$RegistryPath)
    $match = [regex]::Match($RegistryPath, '^HKCU:\\(.+)$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw "Only HKCU uninstall registration paths are allowed: $RegistryPath" }
    return $match.Groups[1].Value
}

function Set-HsmUninstallRegistryValues {
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$StringValues,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$DwordValues,
        [scriptblock]$Verify
    )
    $subKeyPath = Get-HsmRegistrySubKeyPath -RegistryPath $RegistryPath
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
    $key = $null
    try {
        $key = $base.OpenSubKey($subKeyPath, $true)
        $existed = $null -ne $key
        if (-not $existed) { $key = $base.CreateSubKey($subKeyPath) }
        $names = @($StringValues.Keys) + @($DwordValues.Keys) + @("Contact")
        $before = @{}
        foreach ($name in $key.GetValueNames()) {
            if ($names -contains $name) {
                $before[$name] = @{ Value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); Kind = $key.GetValueKind($name) }
            }
        }
        try {
            $key.DeleteValue("Contact", $false)
            foreach ($entry in $StringValues.GetEnumerator()) {
                $key.SetValue($entry.Key, [string]$entry.Value, [Microsoft.Win32.RegistryValueKind]::String)
            }
            foreach ($entry in $DwordValues.GetEnumerator()) {
                $key.SetValue($entry.Key, [int]$entry.Value, [Microsoft.Win32.RegistryValueKind]::DWord)
            }
            if ($Verify) { & $Verify }
        } catch {
            $failure = $_
            foreach ($name in $names) {
                if ($before.ContainsKey($name)) { $key.SetValue($name, $before[$name].Value, $before[$name].Kind) }
                else { $key.DeleteValue($name, $false) }
            }
            if (-not $existed -and $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0) {
                $key.Dispose()
                $key = $null
                $base.DeleteSubKey($subKeyPath, $false)
            }
            throw $failure
        }
    } finally {
        if ($key) { $key.Dispose() }
        $base.Dispose()
    }
}

function Get-HsmUninstallRegistryValues {
    param([Parameter(Mandatory = $true)][string]$RegistryPath)
    $subKeyPath = Get-HsmRegistrySubKeyPath -RegistryPath $RegistryPath
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.OpenSubKey($subKeyPath, $false)
        if (-not $key) { return $null }
        $values = [ordered]@{}
        foreach ($name in $key.GetValueNames()) { $values[$name] = $key.GetValue($name) }
        return [pscustomobject]$values
    } finally {
        if ($key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Remove-HsmUninstallRegistryKey {
    param([Parameter(Mandatory = $true)][string]$RegistryPath)
    $subKeyPath = Get-HsmRegistrySubKeyPath -RegistryPath $RegistryPath
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $view)
        try {
            $baseKey.DeleteSubKeyTree($subKeyPath, $false)
        } finally {
            $baseKey.Dispose()
        }
    }
}

function Get-HsmUninstallCommand {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [switch]$Quiet
    )

    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $quietArgument = if ($Quiet) { " -Quiet" } else { "" }
    return "`"$powershellPath`" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ScriptPath`"$quietArgument"
}

function Get-HsmEstimatedSizeKb {
    param([string]$JsAddonsPath, [string]$UninstallRoot)

    $bytes = [long]0
    foreach ($root in @($JsAddonsPath, $UninstallRoot)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $files = if ($root -eq $JsAddonsPath) {
            Get-HsmOwnedPluginDirectories $root @("WpsHighSchoolMath","WpsHighSchoolMathPpt") (Join-Path $root "publish.xml") |
                ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue }
        } else {
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue
        }
        $measure = $files | Measure-Object -Property Length -Sum
        if ($measure.Sum) { $bytes += [long]$measure.Sum }
    }
    return [Math]::Max(1, [int][Math]::Ceiling($bytes / 1KB))
}

function Resolve-HsmUninstallSourceFile {
    param([string]$SourceRoot, [string]$PackagedName, [string]$SourceName)

    $packagedPath = Join-Path $SourceRoot $PackagedName
    if (Test-Path -LiteralPath $packagedPath -PathType Leaf) { return $packagedPath }
    $sourcePath = Join-Path $SourceRoot $SourceName
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) { return $sourcePath }
    throw "Required uninstall component was not found: $PackagedName"
}

function Register-HsmUninstaller {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$JsAddonsPath,
        [string]$UninstallRoot,
        [string]$RegistryPath,
        [string]$StartMenuDirectory
    )

    $paths = Get-HsmUninstallPaths -UninstallRoot $UninstallRoot -RegistryPath $RegistryPath -StartMenuDirectory $StartMenuDirectory
    $legacyRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\WpsHighSchoolMath"))
    $previous = Get-HsmUninstallRegistryValues $paths.RegistryPath
    $legacyRegistered = -not $UninstallRoot -and $previous -and $previous.DisplayName -eq $script:HsmUninstallDisplayName -and
        $previous.UninstallString -eq (Get-HsmUninstallCommand (Join-Path $legacyRoot "uninstall.ps1"))
    $components = @(
        @{ Packaged = "uninstall.ps1"; Source = "offline-uninstall.ps1"; Destination = $paths.ScriptPath },
        @{ Packaged = "uninstall-cleanup.ps1"; Source = "offline-uninstall-cleanup.ps1"; Destination = $paths.CleanupScriptPath },
        @{ Packaged = "uninstall-registration.ps1"; Source = "uninstall-registration.ps1"; Destination = $paths.RegistrationScriptPath },
        @{ Packaged = "addin-maintenance.ps1"; Source = "addin-maintenance.ps1"; Destination = $paths.MaintenanceScriptPath }
    )
    $originalFiles = @{}
    $changedFiles = @()
    $newDirectories = @(@($paths.Root, $paths.StartMenuDirectory) | Where-Object { -not (Test-Path -LiteralPath $_) })
    foreach ($component in $components) {
        $component.SourcePath = Resolve-HsmUninstallSourceFile -SourceRoot $SourceRoot -PackagedName $component.Packaged -SourceName $component.Source
    }
    foreach ($file in @($components.Destination) + $paths.ShortcutPath) {
        if ([IO.File]::Exists($file)) { $originalFiles[$file] = [IO.File]::ReadAllBytes($file) }
    }

    $uninstallCommand = Get-HsmUninstallCommand -ScriptPath $paths.ScriptPath
    $quietUninstallCommand = Get-HsmUninstallCommand -ScriptPath $paths.ScriptPath -Quiet
    $registryValues = [ordered]@{
        DisplayName = $script:HsmUninstallDisplayName
        DisplayVersion = $Version
        Publisher = "高中数学工具"
        InstallDate = Get-Date -Format "yyyyMMdd"
        InstallLocation = $JsAddonsPath
        DisplayIcon = (Join-Path $env:SystemRoot "System32\shell32.dll") + ",31"
        UninstallString = $uninstallCommand
        QuietUninstallString = $quietUninstallCommand
        Comments = "WPS 文字与演示高中数学工具，全部功能免费，支持离线使用。"
    }
    $dwordValues = @{
        NoModify = 1
        NoRepair = 1
    }
    $defaultUninstallRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\WpsHighSchoolMath-Uninstaller"))
    $shortcutTargetScript = if ($paths.Root.Equals($defaultUninstallRoot, [StringComparison]::OrdinalIgnoreCase)) {
        "%LOCALAPPDATA%\Programs\WpsHighSchoolMath-Uninstaller\uninstall.ps1"
    } else {
        $paths.ScriptPath
    }
$startMenuCommand = @"
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "$shortcutTargetScript"
"@
    $shortcutEncoding = if ($startMenuCommand -match '[^\u0000-\u007F]') { New-Object Text.UTF8Encoding($false) } else { New-Object Text.ASCIIEncoding }
    try {
        [void](New-Item -ItemType Directory -Path $paths.Root, $paths.StartMenuDirectory -Force)
        foreach ($component in $components) {
            $changedFiles += $component.Destination
            Copy-Item -LiteralPath $component.SourcePath -Destination $component.Destination -Force
        }
        $changedFiles += $paths.ShortcutPath
        [IO.File]::WriteAllText($paths.ShortcutPath, $startMenuCommand, $shortcutEncoding)
        $dwordValues.EstimatedSize = Get-HsmEstimatedSizeKb -JsAddonsPath $JsAddonsPath -UninstallRoot $paths.Root
        $result = Set-HsmUninstallRegistryValues -RegistryPath $paths.RegistryPath -StringValues $registryValues -DwordValues $dwordValues -Verify {
            Test-HsmUninstallerRegistration -Version $Version -UninstallRoot $paths.Root -RegistryPath $paths.RegistryPath -StartMenuDirectory $paths.StartMenuDirectory
        }
    } catch {
        $failure = $_
        foreach ($file in $changedFiles) {
            if ($originalFiles.ContainsKey($file)) { [IO.File]::WriteAllBytes($file, $originalFiles[$file]) }
            elseif ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
        }
        foreach ($directory in $newDirectories) {
            if ([IO.Directory]::Exists($directory) -and [IO.Directory]::GetFileSystemEntries($directory).Length -eq 0) {
                [IO.Directory]::Delete($directory, $false)
            }
        }
        throw $failure
    }
    # Only a distinct, older 32-bit entry can have a different version after the verified 64-bit write.
    $base32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry32)
    try {
        $subKey = Get-HsmRegistrySubKeyPath $paths.RegistryPath
        $legacy = $base32.OpenSubKey($subKey)
        if ($legacy) {
            try {
                $obsolete = $legacy.GetValue("DisplayName") -eq $script:HsmUninstallDisplayName -and $legacy.GetValue("DisplayVersion") -ne $Version
            } finally { $legacy.Dispose() }
            if ($obsolete) { $base32.DeleteSubKey($subKey, $false) }
        }
    } catch { Write-Warning "Old Windows uninstall entry retained: $($_.Exception.Message)" }
    finally { $base32.Dispose() }
    if ($legacyRegistered -and [IO.Directory]::Exists($legacyRoot) -and
        -not ((Get-Item -LiteralPath $legacyRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        try {
            foreach ($oldFile in @("uninstall.ps1","uninstall-cleanup.ps1","uninstall-registration.ps1")) {
                [IO.File]::Delete((Join-Path $legacyRoot $oldFile))
            }
            if ([IO.Directory]::GetFileSystemEntries($legacyRoot).Count -eq 0) { [IO.Directory]::Delete($legacyRoot) }
        } catch { Write-Warning "The previous uninstall files are still in use: $legacyRoot" }
    }
    return $result
}

function Test-HsmUninstallerRegistration {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [string]$UninstallRoot,
        [string]$RegistryPath,
        [string]$StartMenuDirectory
    )

    $paths = Get-HsmUninstallPaths -UninstallRoot $UninstallRoot -RegistryPath $RegistryPath -StartMenuDirectory $StartMenuDirectory
    foreach ($filePath in @($paths.ScriptPath, $paths.CleanupScriptPath, $paths.RegistrationScriptPath, $paths.MaintenanceScriptPath, $paths.ShortcutPath)) {
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Installed uninstaller component is missing: $filePath"
        }
    }
    $entry = Get-HsmUninstallRegistryValues -RegistryPath $paths.RegistryPath
    if (-not $entry) {
        throw "Windows uninstall registration is missing: $($paths.RegistryPath)"
    }
    if ([string]$entry.DisplayName -ne $script:HsmUninstallDisplayName -or
        [string]$entry.DisplayVersion -ne $Version -or
        [string]$entry.UninstallString -notlike "*uninstall.ps1*" -or
        [string]$entry.QuietUninstallString -notlike "*uninstall.ps1* -Quiet") {
        throw "Windows uninstall registration is inconsistent with version $Version."
    }
    return [pscustomobject][ordered]@{
        DisplayName = [string]$entry.DisplayName
        Version = [string]$entry.DisplayVersion
        Root = $paths.Root
        RegistryPath = $paths.RegistryPath
        ShortcutPath = $paths.ShortcutPath
        EstimatedSizeKb = [int]$entry.EstimatedSize
    }
}

function Unregister-HsmUninstaller {
    param(
        [string]$UninstallRoot,
        [string]$RegistryPath,
        [string]$StartMenuDirectory
    )

    $paths = Get-HsmUninstallPaths -UninstallRoot $UninstallRoot -RegistryPath $RegistryPath -StartMenuDirectory $StartMenuDirectory
    Remove-HsmUninstallRegistryKey -RegistryPath $paths.RegistryPath
    if (Test-Path -LiteralPath $paths.ShortcutPath -PathType Leaf) {
        Remove-Item -LiteralPath $paths.ShortcutPath -Force
    }
    if (Test-Path -LiteralPath $paths.StartMenuDirectory -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $paths.StartMenuDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $paths.StartMenuDirectory -Force
        }
    }
    return $paths
}
