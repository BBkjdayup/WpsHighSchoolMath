param(
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

$pluginName = "__PLUGIN_NAME__"
$pptPluginName = "__PPT_PLUGIN_NAME__"
$pluginVersion = "__PLUGIN_VERSION__"
$plugins = @(
    @{ Name = $pluginName; Type = "wps"; FolderName = "${pluginName}_${pluginVersion}"; ManifestSha256 = "__WRITER_PAYLOAD_MANIFEST_SHA256__" },
    @{ Name = $pptPluginName; Type = "wpp"; FolderName = "${pptPluginName}_${pluginVersion}"; ManifestSha256 = "__PPT_PAYLOAD_MANIFEST_SHA256__" }
)
$stalePluginNames = @($pluginName, "${pluginName}E2E3", $pptPluginName)

$integrityScript = Join-Path $PSScriptRoot "payload-integrity.ps1"
if (-not (Test-Path -LiteralPath $integrityScript -PathType Leaf)) {
    throw "Payload integrity helper was not found: $integrityScript"
}
. $integrityScript

$uninstallRegistrationScript = Join-Path $PSScriptRoot "uninstall-registration.ps1"
if (-not (Test-Path -LiteralPath $uninstallRegistrationScript -PathType Leaf)) {
    throw "Uninstall registration helper was not found: $uninstallRegistrationScript"
}
. $uninstallRegistrationScript

function Save-XmlDocument {
    param(
        [xml]$Document,
        [string]$Path
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = Join-Path $directory ("." + [IO.Path]::GetFileName($Path) + "." + [Guid]::NewGuid().ToString("N") + ".tmp")
    $replaceBackupPath = $temporaryPath + ".bak"
    $writer = [System.Xml.XmlWriter]::Create($temporaryPath, $settings)
    try {
        $Document.Save($writer)
    } finally {
        $writer.Dispose()
    }
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $Path, $replaceBackupPath)
            Remove-Item -LiteralPath $replaceBackupPath -Force
        } else {
            [IO.File]::Move($temporaryPath, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        if (Test-Path -LiteralPath $replaceBackupPath -PathType Leaf) {
            Remove-Item -LiteralPath $replaceBackupPath -Force
        }
    }
}

function Set-IniValue {
    param(
        [string]$Content,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )

    $newline = "`r`n"
    $sectionName = [regex]::Escape($Section)
    $keyName = [regex]::Escape($Key)
    $sectionPattern = "(?ims)(^\s*\[$sectionName\]\s*\r?\n)(.*?)(?=^\s*\[|\z)"
    $sectionRegex = New-Object regex($sectionPattern)

    if (-not $sectionRegex.IsMatch($Content)) {
        return $Content.TrimEnd() + $newline + $newline + "[$Section]" + $newline + "$Key=$Value" + $newline
    }

    return $sectionRegex.Replace($Content, {
        param($match)

        $header = $match.Groups[1].Value
        $body = $match.Groups[2].Value
        $keyPattern = "(?im)^\s*$keyName\s*=.*$"
        if ([regex]::IsMatch($body, $keyPattern)) {
            $body = [regex]::Replace($body, $keyPattern, "$Key=$Value")
        } else {
            $body = $body.TrimEnd() + $newline + "$Key=$Value" + $newline
        }
        return $header + $body
    }, 1)
}

function Get-WpsOemIniPath {
    $command = (Get-ItemProperty -LiteralPath "Registry::HKEY_CLASSES_ROOT\KWPS.Document.12\shell\open\command")."(default)"
    $match = [regex]::Match([string]$command, '"([^"]+\.exe)"|^([^\s]+\.exe)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $wpsExe = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
    return Join-Path (Split-Path -Parent $wpsExe) "cfgs\oem.ini"
}

function Set-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $property.Value = $Value
    }
}

function Update-AuthorizationCache {
    param(
        [string]$Path,
        [object[]]$Plugins,
        [string]$JsAddonsPath,
        [string]$BackupPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $authorization = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "WPS add-in authorization cache could not be read. Existing entries were left unchanged."
        return
    }

    $changed = $false
    foreach ($pluginInfo in $Plugins) {
        $hostName = [string]$pluginInfo.Type
        $pluginNameToUpdate = [string]$pluginInfo.Name
        $hostProperty = $authorization.PSObject.Properties[$hostName]
        if ($null -eq $hostProperty) {
            continue
        }

        $hostCache = $hostProperty.Value
        if ($null -eq $hostCache) {
            continue
        }

        $matchingProperties = @(
            $hostCache.PSObject.Properties |
                Where-Object {
                    $_.Name -ne "namelist" -and
                    $null -ne $_.Value -and
                    [string]$_.Value.name -eq $pluginNameToUpdate
                }
        )
        if ($matchingProperties.Count -eq 0) {
            continue
        }

        $targetPath = (Join-Path $JsAddonsPath ([string]$pluginInfo.FolderName)).Replace('\', '/')
        $normalizedTargetPath = $targetPath.TrimEnd('/').ToLowerInvariant()
        $preserveApproval = [bool]$pluginInfo.PreserveApproval
        $currentProperties = @()
        if ($preserveApproval) {
            $currentProperties = @(
                $matchingProperties |
                    Where-Object {
                        $candidatePath = ([string]$_.Value.path).Replace('\', '/').TrimEnd('/').ToLowerInvariant()
                        [string]$_.Value.mode -eq "1" -and
                        [string]$_.Value.path -notmatch '^https?://' -and
                        $candidatePath -eq $normalizedTargetPath
                    }
            )
        }

        # A WPS trust fingerprint is tied to the exact local package. Carrying a
        # fingerprint from an older version into a new folder makes WPS show a
        # "modified" warning without fully loading the ribbon. Preserve a
        # current-package approval, but remove stale approvals so WPS can create
        # a fresh fingerprint after the user confirms the normal trust prompt.
        $selectedProperty = if ($currentProperties.Count -gt 0) { $currentProperties[0] } else { $null }
        $selectedKey = if ($null -eq $selectedProperty) { "" } else { [string]$selectedProperty.Name }

        $keysToRemove = @(
            $matchingProperties |
                Where-Object { -not $selectedKey -or $_.Name -ne $selectedKey } |
                ForEach-Object { $_.Name }
        )
        foreach ($key in $keysToRemove) {
            [void]$hostCache.PSObject.Properties.Remove($key)
            $changed = $true
        }

        $nameListProperty = $hostCache.PSObject.Properties["namelist"]
        $existingNameList = if ($null -eq $nameListProperty) { "" } else { [string]$nameListProperty.Value }
        $seenKeys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $remainingKeys = @(
            ($existingNameList -split ";") |
                Where-Object {
                    $_ -and
                    $keysToRemove -notcontains $_ -and
                    $seenKeys.Add($_)
                }
        )
        if ($selectedKey -and -not $seenKeys.Contains($selectedKey)) {
            $remainingKeys += $selectedKey
        }
        $updatedNameList = $remainingKeys -join ";"
        if ($updatedNameList -ne $existingNameList) {
            Set-ObjectPropertyValue -Object $hostCache -Name "namelist" -Value $updatedNameList
            $changed = $true
        }
    }

    if (-not $changed) {
        return
    }

    if (-not $BackupPath) { $BackupPath = "$Path.math-plugin-backup-$([Guid]::NewGuid().ToString('N'))" }
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    $json = $authorization | ConvertTo-Json -Depth 16
    Write-Utf8TextAtomic -Path $Path -Content $json
}

function Stop-LocalEditorHosts {
    param([string[]]$AllowedRoots)

    $normalizedRoots = @(
        $AllowedRoots |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                [IO.Path]::GetFullPath($_).TrimEnd(
                    [IO.Path]::DirectorySeparatorChar,
                    [IO.Path]::AltDirectorySeparatorChar
                ) + [IO.Path]::DirectorySeparatorChar
            }
    )
    foreach ($process in @(Get-Process -Name "WpsHighSchoolMathEditorHost" -ErrorAction SilentlyContinue)) {
        $processPath = $null
        try { $processPath = $process.Path } catch { $processPath = $null }
        if (-not $processPath) {
            continue
        }
        $fullProcessPath = [IO.Path]::GetFullPath($processPath)
        $isOwnedHost = @(
            $normalizedRoots |
                Where-Object { $fullProcessPath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
        ).Count -gt 0
        if (-not $isOwnedHost) {
            continue
        }
        $processId = $process.Id
        Stop-Process -Id $processId -Force -ErrorAction Stop
        Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
    }
}

function Update-HsmPublishRegistration {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Plugins,
        [Parameter(Mandatory = $true)][string[]]$StaleNames,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [xml]$publishXml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } else {
        [xml]$publishXml = "<jsplugins />"
    }
    $root = $publishXml.DocumentElement
    foreach ($name in $StaleNames) {
        @($root.SelectNodes("*[@name='$name']")) | ForEach-Object {
            [void]$root.RemoveChild($_)
        }
    }
    foreach ($pluginInfo in $Plugins) {
        $plugin = $publishXml.CreateElement("jsplugin")
        $attributes = [ordered]@{
            name = $pluginInfo.Name
            type = $pluginInfo.Type
            url = $pluginInfo.FolderName
            version = $Version
            enable = "enable_dev"
            install = "null"
            customDomain = ""
        }
        foreach ($entry in $attributes.GetEnumerator()) {
            $plugin.SetAttribute($entry.Key, [string]$entry.Value)
        }
        [void]$root.AppendChild($plugin)
    }
    Save-XmlDocument -Document $publishXml -Path $Path
}

function Test-HsmInstalledState {
    param(
        [Parameter(Mandatory = $true)][string]$JsAddonsPath,
        [Parameter(Mandatory = $true)][string]$PublishPath,
        [Parameter(Mandatory = $true)][object[]]$Plugins,
        [Parameter(Mandatory = $true)][string]$Product,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if (-not (Test-Path -LiteralPath $PublishPath -PathType Leaf)) {
        throw "publish.xml was not created by the install transaction."
    }
    [xml]$publishXml = Get-Content -LiteralPath $PublishPath -Raw -Encoding UTF8
    $root = $publishXml.DocumentElement
    $results = @()
    foreach ($pluginInfo in $Plugins) {
        $payloadPath = Join-Path $JsAddonsPath $pluginInfo.FolderName
        $payloadResult = Test-HsmPayload `
            -PayloadPath $payloadPath `
            -ExpectedProduct $Product `
            -ExpectedPluginName $pluginInfo.Name `
            -ExpectedVersion $Version `
            -ExpectedHostType $pluginInfo.Type `
            -ExpectedManifestSha256 $pluginInfo.ManifestSha256
        $nodes = @($root.SelectNodes("*[@name='$($pluginInfo.Name)']"))
        if ($nodes.Count -ne 1) {
            throw "Expected exactly one publish.xml entry for $($pluginInfo.Name); found $($nodes.Count)."
        }
        $node = $nodes[0]
        if ($node.GetAttribute("type") -ne $pluginInfo.Type -or
            $node.GetAttribute("url") -ne $pluginInfo.FolderName -or
            $node.GetAttribute("version") -ne $Version -or
            $node.GetAttribute("enable") -ne "enable_dev") {
            throw "publish.xml registration is inconsistent with the installed $($pluginInfo.Type) payload."
        }
        $results += $payloadResult
    }
    return @($results)
}

function Invoke-HsmInstallTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerRoot,
        [Parameter(Mandatory = $true)][string]$JsAddonsPath,
        [Parameter(Mandatory = $true)][string]$PublishPath,
        [Parameter(Mandatory = $true)][string]$AuthorizationPath,
        [Parameter(Mandatory = $true)][object[]]$Plugins,
        [Parameter(Mandatory = $true)][string[]]$StaleNames,
        [Parameter(Mandatory = $true)][string]$Product,
        [Parameter(Mandatory = $true)][string]$Version,
        [scriptblock]$TestCheckpoint,
        [scriptblock]$RegisterUninstaller
    )

    Repair-HsmPendingTransactions $JsAddonsPath $StaleNames $RegisterUninstaller
    $transactionRoot = Join-Path $JsAddonsPath (".hsm-install-v1-" + [Guid]::NewGuid().ToString("N").Substring(0, 12))
    $stageRoot = Join-Path $transactionRoot "new"
    $backupRoot = Join-Path $transactionRoot "backup"
    $backupPayloadRoot = Join-Path $backupRoot "payloads"
    $configRoot = Join-Path $transactionRoot "config"
    $trustBackup = Join-Path $backupRoot "trust-before-write.json"
    $registering = Join-Path $transactionRoot "registering"
    $committed = Join-Path $transactionRoot "committed"
    $targets = @()
    $results = @()
    try {
        New-Item -ItemType Directory -Path $stageRoot, $backupPayloadRoot, $configRoot -Force | Out-Null
        $owned = @(Get-HsmOwnedPluginDirectories $JsAddonsPath $StaleNames $PublishPath)
        $ownedNames = @($owned | ForEach-Object Name)
        foreach ($plugin in $Plugins) {
            $check = @{
                ExpectedProduct = $Product; ExpectedPluginName = $plugin.Name
                ExpectedVersion = $Version; ExpectedHostType = $plugin.Type
            }
            $source = Join-Path $InstallerRoot ("payload\" + $plugin.FolderName)
            $sourceResult = Test-HsmPayload @check -PayloadPath $source -ExpectedManifestSha256 $plugin.ManifestSha256
            $live = Get-HsmTransactionFolder $JsAddonsPath $plugin.FolderName $StaleNames
            $exists = [IO.Directory]::Exists($live)
            if ($exists -and $ownedNames -notcontains $plugin.FolderName) {
                throw "The destination belongs to an unidentified add-in: $live"
            }
            $plugin["PreserveApproval"] = $exists -and
                (Test-HsmPayloadEquivalent @check -PayloadPath $live -ExpectedPayloadSha256 $sourceResult.PayloadSha256) -and
                (Get-HsmSha256 (Join-Path $live "PAYLOAD-MANIFEST.json")) -eq $plugin.ManifestSha256
            $stage = Join-Path $stageRoot $plugin.FolderName
            if ($TestCheckpoint) { & $TestCheckpoint ("before-stage-copy-" + $plugin.Type) }
            Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
            [void](Test-HsmPayload @check -PayloadPath $stage -ExpectedManifestSha256 $plugin.ManifestSha256)
            if (-not $plugin.PreserveApproval) {
                $targets += @{ folder = $plugin.FolderName; existed = $exists; manifestHash = $plugin.ManifestSha256 }
            }
        }
        if ($TestCheckpoint) { & $TestCheckpoint "after-stage" }

        foreach ($file in @($PublishPath, $AuthorizationPath)) {
            if ([IO.File]::Exists($file)) {
                $leaf = [IO.Path]::GetFileName($file)
                Copy-Item -LiteralPath $file -Destination (Join-Path $backupRoot $leaf)
                Copy-Item -LiteralPath $file -Destination (Join-Path $configRoot $leaf)
            }
        }
        Update-AuthorizationCache -Path (Join-Path $configRoot "authaddin.json") -Plugins $Plugins -JsAddonsPath $JsAddonsPath -BackupPath $trustBackup
        Update-HsmPublishRegistration -Path (Join-Path $configRoot "publish.xml") -Plugins $Plugins -StaleNames $StaleNames -Version $Version
        if ($RegisterUninstaller) {
            $control = New-Item -ItemType Directory -Path (Join-Path $transactionRoot "control")
            foreach ($name in @("uninstall.ps1", "uninstall-cleanup.ps1", "uninstall-registration.ps1", "addin-maintenance.ps1")) {
                Copy-Item -LiteralPath (Join-Path $InstallerRoot $name) -Destination $control.FullName
            }
        }
        $activeFolders = @($Plugins | ForEach-Object { $_.FolderName })
        $journal = [ordered]@{ schema = 1; product = $Product; version = $Version; targets = $targets
            retire = @($ownedNames | Where-Object { $activeFolders -notcontains $_ }) }
        Write-Utf8TextAtomic (Join-Path $transactionRoot "transaction.json") ($journal | ConvertTo-Json -Depth 5)
        if ($TestCheckpoint) { & $TestCheckpoint "after-backup" }

        $count = 0
        foreach ($plugin in $Plugins) {
            $folder = $plugin.FolderName
            $target = $targets | Where-Object { $_.folder -eq $folder }
            if ($target) {
                $live = Get-HsmTransactionFolder $JsAddonsPath $folder $StaleNames
                if ($target.existed) {
                    [IO.Directory]::Move($live, (Join-Path $backupPayloadRoot $folder))
                    if ($TestCheckpoint) { & $TestCheckpoint ("after-displace-" + $plugin.Type) }
                }
                [IO.Directory]::Move((Join-Path $stageRoot $folder), $live)
            }
            $count++
            if ($TestCheckpoint) { & $TestCheckpoint ("after-payload-switch-" + $count) }
        }
        foreach ($file in @($AuthorizationPath, $PublishPath)) {
            $leaf = [IO.Path]::GetFileName($file)
            $next = Join-Path $configRoot $leaf
            $before = Join-Path $backupRoot $leaf
            if ([IO.File]::Exists($next) -and (-not [IO.File]::Exists($before) -or (Get-HsmSha256 $before) -ne (Get-HsmSha256 $next))) {
                if ([IO.File]::Exists($file) -ne [IO.File]::Exists($before) -or
                    ([IO.File]::Exists($file) -and (Get-HsmSha256 $file) -ne (Get-HsmSha256 $before))) {
                    throw "WPS configuration changed during installation. Please retry: $file"
                }
                [IO.File]::WriteAllText((Join-Path $transactionRoot ("writing-" + $leaf)), "")
                Copy-FileAtomic $next $file
            }
            if ($TestCheckpoint) {
                if ($file -eq $AuthorizationPath) { & $TestCheckpoint "after-auth" } else { & $TestCheckpoint "after-publish" }
            }
        }
        $results = @(Test-HsmInstalledState -JsAddonsPath $JsAddonsPath -PublishPath $PublishPath -Plugins $Plugins -Product $Product -Version $Version)
        if ($TestCheckpoint) { & $TestCheckpoint "after-validate" }
        if ($RegisterUninstaller) {
            [IO.File]::WriteAllText($registering, "")
            try { [void](& $RegisterUninstaller $Version $InstallerRoot $JsAddonsPath) }
            catch { [IO.File]::Delete($registering); throw }
            if ($TestCheckpoint) { & $TestCheckpoint "after-register" }
        }
        [IO.File]::WriteAllText($committed, "")
    } catch {
        $failure = $_
        $finishRegistration = [IO.File]::Exists($registering) -or [IO.File]::Exists($committed)
        try {
            if ([IO.Directory]::Exists($transactionRoot)) {
                Complete-HsmTransaction (Get-Item -LiteralPath $transactionRoot) $JsAddonsPath $StaleNames $RegisterUninstaller
            }
        } catch { throw "Install failed: $failure. Rollback also failed; recovery data was kept at $transactionRoot. $_" }
        if ($finishRegistration) { throw "Windows registration was recovered after an installation error: $failure" }
        throw "Install failed and the previous Writer/PPT installation was restored: $($failure.Exception.Message)"
    }
    try {
        if ([IO.File]::Exists($trustBackup)) {
            Copy-Item -LiteralPath $trustBackup -Destination "$AuthorizationPath.math-plugin-backup-$([Guid]::NewGuid().ToString('N'))"
        }
        Complete-HsmTransaction (Get-Item -LiteralPath $transactionRoot) $JsAddonsPath $StaleNames $RegisterUninstaller
    } catch { Write-Warning "Installation verified. Pending cleanup at $transactionRoot. $_" }
    return $results
}

Invoke-HsmMaintenance {
    Assert-HsmWpsClosed

    $jsAddonsPath = Join-Path $env:APPDATA "kingsoft\wps\jsaddons"
    $publishPath = Join-Path $jsAddonsPath "publish.xml"
    $authorizationPath = Join-Path $jsAddonsPath "authaddin.json"
    New-Item -ItemType Directory -Path $jsAddonsPath -Force | Out-Null

    $legacyProductPath = Join-Path $env:APPDATA "WpsHighSchoolMath"
    $ownedRoots = @(Get-HsmOwnedPluginDirectories $jsAddonsPath $stalePluginNames $publishPath | ForEach-Object FullName)
    Stop-LocalEditorHosts -AllowedRoots ($ownedRoots + $legacyProductPath)

    $installedResults = @(Invoke-HsmInstallTransaction `
        -InstallerRoot $PSScriptRoot `
        -JsAddonsPath $jsAddonsPath `
        -PublishPath $publishPath `
        -AuthorizationPath $authorizationPath `
        -Plugins $plugins `
        -StaleNames $stalePluginNames `
        -Product $pluginName `
        -Version $pluginVersion `
        -RegisterUninstaller { param($version, $source, $addons) Register-HsmUninstaller -Version $version -SourceRoot $source -JsAddonsPath $addons })

    $oemPath = Get-WpsOemIniPath
    $oemConfigured = $false
    if ($oemPath -and (Test-Path -LiteralPath $oemPath)) {
        try {
            $oemBackupPath = "$oemPath.math-plugin-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $oemPath -Destination $oemBackupPath -Force
            $oemContent = Get-Content -LiteralPath $oemPath -Raw
            $oemContent = Set-IniValue -Content $oemContent -Section "Support" -Key "JsApiPlugin" -Value "true"
            $oemContent = Set-IniValue -Content $oemContent -Section "Support" -Key "JsApiShowWebDebugger" -Value "false"
            Write-Utf8TextAtomic -Path $oemPath -Content $oemContent
            $oemConfigured = $true
        } catch {
            $configurationScript = Join-Path $PSScriptRoot "configure-wps.ps1"
            if (Test-Path -LiteralPath $configurationScript -PathType Leaf) {
                try {
                    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$configurationScript`""
                    $configurationProcess = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru
                    $oemConfigured = $configurationProcess.ExitCode -eq 0
                } catch {
                    Write-Warning "The add-in is installed, but the optional WPS debugger-button configuration was not approved."
                }
            }
        }
    } else {
        Write-Warning "WPS oem.ini was not found. The plugin was installed, but the JS debugger button could not be disabled."
    }
    if (-not $oemConfigured) {
        Write-Warning "The add-in is installed and usable, but WPS may still show its JS debugger button."
    }

    Write-Host ""
    Write-Host "WPS High School Math $pluginVersion was installed for Writer and Presentation."
    foreach ($result in $installedResults) {
        Write-Host ("Verified {0}: {1} files, payload {2}" -f $result.HostType, $result.FileCount, $result.PayloadSha256)
    }
    Write-Host "Windows uninstall entry: $script:HsmUninstallDisplayName $pluginVersion"
    Write-Host "Restart all WPS Writer and Presentation windows to load the plugin and hide the JS debugger button."
    Write-Host "On the first Writer and Presentation launch after an upgrade, click Confirm when WPS asks whether to trust the add-in."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show(
            "安装完成。`r`n`r`n高中数学工具全部功能永久免费，可以离线使用。`r`n`r`n卸载入口：Windows 设置 → 应用 → 已安装的应用 → WPS 高中数学工具插件。",
            "WPS 高中数学工具插件",
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        Write-Verbose "Unable to show the installation summary: $($_.Exception.Message)"
    }
}
