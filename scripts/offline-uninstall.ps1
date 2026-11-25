param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$pluginName = "__PLUGIN_NAME__"
$pptPluginName = "__PPT_PLUGIN_NAME__"
$stalePluginNames = @($pluginName, "${pluginName}E2E3", $pptPluginName)
$jsAddonsPath = Join-Path $env:APPDATA "kingsoft\wps\jsaddons"
$publishPath = Join-Path $jsAddonsPath "publish.xml"
$authorizationPath = Join-Path $jsAddonsPath "authaddin.json"
$legacyProductPath = Join-Path $env:APPDATA "WpsHighSchoolMath"
$registrationHelper = Join-Path $PSScriptRoot "uninstall-registration.ps1"

if (-not (Test-Path -LiteralPath $registrationHelper -PathType Leaf)) {
    throw "卸载注册组件缺失，请重新运行安装包后再卸载。"
}
. $registrationHelper

function Show-HsmMessage {
    param(
        [string]$Text,
        [string]$Title = "WPS 高中数学工具插件",
        [ValidateSet("Information", "Warning", "Error")][string]$Icon = "Information"
    )
    if ($Quiet) { return }
    Add-Type -AssemblyName System.Windows.Forms
    $iconValue = [Windows.Forms.MessageBoxIcon][Enum]::Parse([Windows.Forms.MessageBoxIcon], $Icon)
    [Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [Windows.Forms.MessageBoxButtons]::OK,
        $iconValue
    ) | Out-Null
}

function Confirm-HsmUninstall {
    if ($Quiet) { return $true }
    Add-Type -AssemblyName System.Windows.Forms
    $choice = [Windows.Forms.MessageBox]::Show(
        "将卸载 WPS 文字版和演示版中的高中数学插件。`r`n`r`n已插入文档和课件的图像仍可正常打开。`r`n`r`n是否继续？",
        "卸载高中数学插件",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question,
        [Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return $choice -eq [Windows.Forms.DialogResult]::Yes
}

function Save-HsmXmlDocument {
    param([xml]$Document, [string]$Path)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $temporaryPath = Join-Path (Split-Path -Parent $Path) ("." + [IO.Path]::GetFileName($Path) + "." + [Guid]::NewGuid().ToString("N") + ".tmp")
    $replaceBackupPath = $temporaryPath + ".bak"
    $writer = [System.Xml.XmlWriter]::Create($temporaryPath, $settings)
    try {
        $Document.Save($writer)
    } finally {
        $writer.Dispose()
    }
    try {
        [IO.File]::Replace($temporaryPath, $Path, $replaceBackupPath)
        Remove-Item -LiteralPath $replaceBackupPath -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        if (Test-Path -LiteralPath $replaceBackupPath -PathType Leaf) {
            Remove-Item -LiteralPath $replaceBackupPath -Force
        }
    }
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
        if (-not $processPath) { continue }
        $fullProcessPath = [IO.Path]::GetFullPath($processPath)
        $isOwnedHost = @($normalizedRoots | Where-Object { $fullProcessPath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $isOwnedHost) { continue }
        $processId = $process.Id
        Stop-Process -Id $processId -Force -ErrorAction Stop
        Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
    }
}

function Remove-HsmPluginDirectories {
    param([string]$JsAddonsPath, [string[]]$PluginNames)

    $publish = Join-Path $JsAddonsPath "publish.xml"
    foreach ($directory in Get-HsmOwnedPluginDirectories $JsAddonsPath $PluginNames $publish) {
        Remove-HsmSafeDirectory $directory.FullName $JsAddonsPath
    }
}

function Remove-HsmPublishEntries {
    param([string]$Path, [string[]]$PluginNames)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    [xml]$document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $changed = $false
    foreach ($name in $PluginNames) {
        foreach ($node in @($document.DocumentElement.SelectNodes("*[@name='$name']"))) {
            [void]$document.DocumentElement.RemoveChild($node)
            $changed = $true
        }
    }
    if ($changed) { Save-HsmXmlDocument -Document $document -Path $Path }
}

function Remove-HsmAuthorizationEntries {
    param([string]$Path, [string[]]$PluginNames)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $authorization = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $changed = $false
    foreach ($hostName in @("wps", "wpp")) {
        $hostProperty = $authorization.PSObject.Properties[$hostName]
        if ($null -eq $hostProperty -or $null -eq $hostProperty.Value) { continue }
        $hostBucket = $hostProperty.Value
        $removeKeys = @(
            $hostBucket.PSObject.Properties |
                Where-Object {
                    $_.Name -ne "namelist" -and $_.Value -and $PluginNames -contains [string]$_.Value.name
                } |
                Select-Object -ExpandProperty Name
        )
        foreach ($key in $removeKeys) {
            [void]$hostBucket.PSObject.Properties.Remove($key)
            $changed = $true
        }
        $nameListProperty = $hostBucket.PSObject.Properties["namelist"]
        if ($nameListProperty) {
            $oldNames = @(([string]$nameListProperty.Value).Split(";", [StringSplitOptions]::RemoveEmptyEntries))
            $newNames = @($oldNames | Where-Object { $removeKeys -notcontains $_ } | Select-Object -Unique)
            $newValue = $newNames -join ";"
            if ($newValue -ne [string]$nameListProperty.Value) {
                $nameListProperty.Value = $newValue
                $changed = $true
            }
        }
    }
    if ($changed) {
        Write-Utf8TextAtomic -Path $Path -Content ($authorization | ConvertTo-Json -Depth 32)
    }
}

function Start-HsmUninstallSelfCleanup {
    param([object]$Paths)

    if (-not $Paths -or -not (Test-Path -LiteralPath $Paths.CleanupScriptPath -PathType Leaf)) { return }
    $retired = Move-HsmUninstallRootAside $Paths.Root
    $cleaner = Join-Path $retired "uninstall-cleanup.ps1"
    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$cleaner`" -TargetRoot `"$retired`" -ParentProcessId $PID"
    Start-Process -FilePath $powershellPath -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

function Invoke-HsmUninstall {
    Assert-HsmWpsClosed
    if (-not (Confirm-HsmUninstall)) { return $false }

    $ownedRoots = @(Get-HsmOwnedPluginDirectories $jsAddonsPath $stalePluginNames $publishPath | ForEach-Object FullName)
    Stop-LocalEditorHosts -AllowedRoots ($ownedRoots + $legacyProductPath)
    Repair-HsmPendingTransactions -Root $jsAddonsPath -PluginNames $stalePluginNames -Removing
    Remove-HsmPluginDirectories -JsAddonsPath $jsAddonsPath -PluginNames @($pluginName, $pptPluginName)
    Remove-HsmPublishEntries -Path $publishPath -PluginNames $stalePluginNames
    Remove-HsmAuthorizationEntries -Path $authorizationPath -PluginNames $stalePluginNames
    $uninstallPaths = Unregister-HsmUninstaller

    Start-HsmUninstallSelfCleanup -Paths $uninstallPaths
    Show-HsmMessage -Text "高中数学插件已卸载。`r`n`r`n文档和课件中的图像仍可使用。" -Icon "Information"
    return $true
}

try {
    [void](Invoke-HsmMaintenance { Invoke-HsmUninstall })
} catch {
    Show-HsmMessage -Text $_.Exception.Message -Title "卸载失败" -Icon "Error"
    Write-Error $_
    exit 1
}
