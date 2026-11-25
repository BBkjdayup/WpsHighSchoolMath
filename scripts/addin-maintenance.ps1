function Assert-HsmWpsClosed {
    param([object[]]$Processes = @(Get-Process -Name "wps", "wpp" -ErrorAction SilentlyContinue))

    if ($Processes.Count -gt 0) {
        throw "请先保存文档并退出 WPS 文字和演示。后台自动化也可能持有未保存的文档，请在任务结束后重试。"
    }
}

function Test-HsmVersionFolder {
    param([string]$Folder, [string]$PluginName)

    return $Folder -match ('^' + [regex]::Escape($PluginName) + '_[0-9]+(?:\.[0-9]+){1,3}(?:-[A-Za-z0-9.-]+)?$')
}

function Get-HsmOwnedPluginDirectories {
    param([string]$Root, [string[]]$PluginNames, [string]$PublishPath)

    if (-not [IO.Directory]::Exists($Root)) { return }
    $registrations = @()
    if ([IO.File]::Exists($PublishPath)) {
        [xml]$publish = [IO.File]::ReadAllText($PublishPath)
        $registrations = @($publish.DocumentElement.SelectNodes("*[@url and @name]"))
    }
    foreach ($directory in Get-ChildItem -LiteralPath $Root -Directory) {
        foreach ($name in $PluginNames) {
            if (-not (Test-HsmVersionFolder $directory.Name $name)) { continue }
            if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $entries = @($registrations | Where-Object { $_.GetAttribute("url") -eq $directory.Name })
            if (@($entries | Where-Object { $_.GetAttribute("name") -ne $name }).Count) { continue }
            $manifestPath = Join-Path $directory.FullName "manifest.xml"
            if ([IO.File]::Exists($manifestPath)) {
                try {
                    [xml]$manifest = [IO.File]::ReadAllText($manifestPath)
                    $identity = $manifest.SelectSingleNode("/*[local-name()='JsPlugin']/*[local-name()='Name']")
                    if (-not $identity -or $identity.InnerText -ne $name) { continue }
                } catch { continue }
            } elseif ($entries.Count -eq 0) { continue }
            $directory
            break
        }
    }
}

function Get-HsmTransactionFolder {
    param([string]$Root, [string]$Leaf, [string[]]$PluginNames)

    if (-not @($PluginNames | Where-Object { Test-HsmVersionFolder $Leaf $_ }).Count) {
        throw "Invalid add-in folder in install journal: $Leaf"
    }
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Leaf))
    if ([IO.Path]::GetDirectoryName($path) -ne [IO.Path]::GetFullPath($Root).TrimEnd('\')) {
        throw "Invalid install journal path: $path"
    }
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to change a linked add-in directory: $path"
    }
    return $path
}

function Write-Utf8TextAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = Join-Path $directory ("." + [IO.Path]::GetFileName($Path) + "." + [Guid]::NewGuid().ToString("N") + ".tmp")
    $replaceBackupPath = $temporaryPath + ".bak"
    try {
        [IO.File]::WriteAllText($temporaryPath, $Content, (New-Object Text.UTF8Encoding($false)))
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

function Copy-FileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $directory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = Join-Path $directory ("." + [IO.Path]::GetFileName($Destination) + "." + [Guid]::NewGuid().ToString("N") + ".tmp")
    $replaceBackupPath = $temporaryPath + ".bak"
    try {
        Copy-Item -LiteralPath $Source -Destination $temporaryPath -Force
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $Destination, $replaceBackupPath)
            Remove-Item -LiteralPath $replaceBackupPath -Force
        } else {
            [IO.File]::Move($temporaryPath, $Destination)
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

function Assert-HsmChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the WPS jsaddons root: $fullPath"
    }
    return $fullPath
}

function Remove-HsmSafeDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $safePath = Assert-HsmChildPath -Path $Path -Root $Root
    Remove-Item -LiteralPath $safePath -Recurse -Force
}

function Restore-HsmTransactionConfig {
    param($Transaction, [string]$Root, [string]$File, [string[]]$PluginNames)

    $live = Join-Path $Root $File
    $before = Join-Path $Transaction "backup\$File"
    $after = Join-Path $Transaction "config\$File"
    if (-not [IO.File]::Exists($live)) { return }
    $currentHash = (Get-FileHash -LiteralPath $live).Hash
    if ([IO.File]::Exists($before) -and (Get-FileHash -LiteralPath $before).Hash -eq $currentHash) { return }
    if ([IO.File]::Exists($after) -and (Get-FileHash -LiteralPath $after).Hash -eq $currentHash) {
        if ([IO.File]::Exists($before)) { Copy-FileAtomic $before $live }
        else { Remove-Item -LiteralPath $live -Force }
        return
    }
    # Another add-in may have registered since a crash. Undo only our entries.
    if ($File -eq "publish.xml") {
        [xml]$current = [IO.File]::ReadAllText($live)
        foreach ($node in @($current.DocumentElement.SelectNodes("*[@name]"))) {
            if ($PluginNames -contains $node.GetAttribute("name")) { [void]$current.DocumentElement.RemoveChild($node) }
        }
        if ([IO.File]::Exists($before)) {
            [xml]$previous = [IO.File]::ReadAllText($before)
            foreach ($node in $previous.DocumentElement.SelectNodes("*[@name]")) {
                if ($PluginNames -contains $node.GetAttribute("name")) {
                    [void]$current.DocumentElement.AppendChild($current.ImportNode($node, $true))
                }
            }
        }
        Write-Utf8TextAtomic $live $current.OuterXml
    } elseif ([IO.File]::Exists($before)) {
        # Installation only removes stale trust records. Preserve later approvals.
        $current = [IO.File]::ReadAllText($live) | ConvertFrom-Json
        $previous = [IO.File]::ReadAllText($before) | ConvertFrom-Json
        foreach ($hostKey in @("wps", "wpp")) {
            $old = $previous.$hostKey
            $bucket = $current.$hostKey
            if (-not $old -or -not $bucket) { continue }
            $listed = @(([string]$bucket.namelist).Split(";", [StringSplitOptions]::RemoveEmptyEntries))
            foreach ($entry in $old.PSObject.Properties) {
                if ($entry.Name -eq "namelist" -or $PluginNames -notcontains $entry.Value.name -or $bucket.PSObject.Properties[$entry.Name]) { continue }
                Add-Member -InputObject $bucket -NotePropertyName $entry.Name -NotePropertyValue $entry.Value
                if (([string]$old.namelist).Split(";") -contains $entry.Name -and $listed -notcontains $entry.Name) {
                    $listed += $entry.Name
                }
            }
            if ($bucket.PSObject.Properties["namelist"]) { $bucket.namelist = $listed -join ";" }
        }
        Write-Utf8TextAtomic $live ($current | ConvertTo-Json -Depth 32)
    }
}

function Complete-HsmTransaction {
    param([IO.DirectoryInfo]$Transaction, [string]$Root, [string[]]$PluginNames, [scriptblock]$RegisterUninstaller, [switch]$Removing)

    $tx = $Transaction.FullName
    if ($Transaction.Parent.FullName -ne [IO.Path]::GetFullPath($Root).TrimEnd('\') -or
        $Transaction.Name -notmatch '^\.hsm-install-v1-[0-9a-f]{12}$' -or ($Transaction.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected install transaction: $tx"
    }
    $journal = Join-Path $tx "transaction.json"
    if ([IO.File]::Exists($journal)) {
        $state = [IO.File]::ReadAllText($journal) | ConvertFrom-Json
        if ($state.schema -ne 1 -or $state.product -ne "WpsHighSchoolMath") { throw "Unrecognized install journal: $journal" }
        $committed = Join-Path $tx "committed"
        if ([IO.File]::Exists((Join-Path $tx "registering")) -and -not [IO.File]::Exists($committed)) {
            # Both hosts were validated. Finish the same Windows registration after a hard exit.
            if (-not $Removing) {
                if (-not $RegisterUninstaller) { throw "The pending Windows uninstall registration must be resumed by the installer." }
                [void](& $RegisterUninstaller $state.version (Join-Path $tx "control") $Root)
            }
            [IO.File]::WriteAllText($committed, "")
        }
        if ([IO.File]::Exists($committed)) {
            $obsolete = @($state.retire)
            $oldPublish = Join-Path $tx "backup\publish.xml"
            $publish = Join-Path $Root "publish.xml"
            if ([IO.File]::Exists($publish)) {
                [xml]$activePublish = [IO.File]::ReadAllText($publish)
                $usedFolders = @($activePublish.DocumentElement.SelectNodes("*[@url]") | ForEach-Object { $_.GetAttribute("url") })
                foreach ($dir in Get-HsmOwnedPluginDirectories $Root $PluginNames $oldPublish) {
                    if ($obsolete -contains $dir.Name -and $usedFolders -notcontains $dir.Name) {
                        [IO.Directory]::Move($dir.FullName, (Join-Path $tx ("backup\payloads\" + $dir.Name)))
                    }
                }
            }
        } else {
            foreach ($target in $state.targets) {
                $live = Get-HsmTransactionFolder $Root $target.folder $PluginNames
                $backup = Join-Path $tx ("backup\payloads\" + $target.folder)
                $staged = Join-Path $tx ("new\" + $target.folder)
                if ([IO.Directory]::Exists($live) -and ([IO.Directory]::Exists($backup) -or
                    (-not $target.existed -and -not [IO.Directory]::Exists($staged)))) {
                    $manifest = Join-Path $live "PAYLOAD-MANIFEST.json"
                    if (-not [IO.File]::Exists($manifest) -or (Get-FileHash -LiteralPath $manifest).Hash -ne $target.manifestHash) {
                        throw "The directory changed after installation was interrupted. Its files and recovery backup have been preserved: $live"
                    }
                    [IO.Directory]::Move($live, (Join-Path $tx ("discard-" + $target.folder)))
                }
                if ([IO.Directory]::Exists($backup)) {
                    [IO.Directory]::Move($backup, $live)
                }
            }
            foreach ($file in @("publish.xml", "authaddin.json")) {
                if ([IO.File]::Exists((Join-Path $tx ("writing-" + $file)))) {
                    Restore-HsmTransactionConfig $tx $Root $file $PluginNames
                }
            }
        }
    }
    if (-not [IO.File]::Exists($journal)) {
        $payloadBackup = Join-Path $tx "backup\payloads"
        if ([IO.Directory]::Exists($payloadBackup) -and [IO.Directory]::GetFileSystemEntries($payloadBackup).Count) {
            throw "Missing install journal. Previous payloads have been preserved at $payloadBackup"
        }
    }
    # Move the completed journal out of the recovery namespace before recursive cleanup.
    $finished = Join-Path $Root ($Transaction.Name.Replace(".hsm-install-v1-", ".hsm-finished-"))
    [IO.Directory]::Move($tx, $finished)
    Remove-HsmSafeDirectory $finished $Root
}

function Repair-HsmPendingTransactions {
    param([string]$Root, [string[]]$PluginNames, [scriptblock]$RegisterUninstaller, [switch]$Removing)

    if (-not [IO.Directory]::Exists($Root)) { return }
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Filter ".hsm-*") {
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($dir.Name -match '^\.hsm-install-v1-[0-9a-f]{12}$') {
            Complete-HsmTransaction $dir $Root $PluginNames $RegisterUninstaller -Removing:$Removing
        } elseif ($dir.Name -match '^\.hsm-finished-[0-9a-f]{12}$') {
            Remove-HsmSafeDirectory $dir.FullName $Root
        } elseif ($dir.Name -match '^\.hsm-install-[0-9a-f]{12}$') {
            # 0.9.0 had no journal. Only restore missing, identifiable directories
            # from its backup; an ambiguous backup may contain someone else's data.
            $backup = Join-Path $dir.FullName "backup\payloads"
            $previousPublish = Join-Path $dir.FullName "backup\publish.xml"
            if (-not [IO.Directory]::Exists($backup)) { continue }
            foreach ($old in Get-HsmOwnedPluginDirectories $backup $PluginNames $previousPublish) {
                $destination = Get-HsmTransactionFolder $Root $old.Name $PluginNames
                if (-not (Test-Path -LiteralPath $destination)) { [IO.Directory]::Move($old.FullName, $destination) }
            }
            if ([IO.Directory]::GetFileSystemEntries($backup).Count -eq 0 -and [IO.File]::Exists($previousPublish)) {
                Remove-HsmSafeDirectory $dir.FullName $Root
            }
        }
    }
}
