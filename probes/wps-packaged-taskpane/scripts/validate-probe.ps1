param(
    [ValidateSet("Source", "Installed")][string]$Mode = "Source",
    [string]$JsAddonsPath = (Join-Path $env:APPDATA "kingsoft\wps\jsaddons")
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "probe-common.ps1")
$manifest = Get-PackagedProbeManifest
if ([string]$manifest.schema -ne "WpsHighSchoolMathPackagedTaskPaneProbe" -or [int]$manifest.version -ne 1 -or [bool]$manifest.commercialPayload) {
    throw "Packaged task-pane probe manifest is invalid."
}
$expected = @($manifest.installedFiles | ForEach-Object { [string]$_ } | Sort-Object)
foreach ($definition in @(Get-PackagedProbeDefinitions)) {
    $source = Join-Path (Join-Path $script:ProbeRoot "src") $definition.Host
    foreach ($name in @("index.html", "main.js", "manifest.xml", "ribbon.xml")) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) { throw "Missing source file: $($definition.Host)/$name" }
    }
    if ($Mode -eq "Installed") {
        $root = Assert-PackagedProbeChildPath -Path (Join-Path $JsAddonsPath $definition.Folder) -Root $JsAddonsPath
        $actual = @(
            Get-ChildItem -LiteralPath $root -Recurse -File |
                ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/') } |
                Sort-Object
        )
        if (($actual -join "|") -ne ($expected -join "|")) { throw "$($definition.Host) installed file set mismatch: $($actual -join ', ')" }
        [xml]$publish = Get-Content -LiteralPath (Join-Path $JsAddonsPath "publish.xml") -Raw -Encoding UTF8
        if (@($publish.DocumentElement.SelectNodes("jsplugin[@name='$($definition.Name)' and @url='$($definition.Folder)']")).Count -ne 1) {
            throw "$($definition.Host) publish registration is missing."
        }
    }
}
foreach ($path in @(
    (Join-Path $script:ProbeRoot "src\shared\probe.js"),
    (Join-Path $script:ProbeRoot "src\shared\pane.js")
)) {
    & node --check $path
    if ($LASTEXITCODE -ne 0) { throw "JavaScript syntax check failed: $path" }
}
$forbiddenPattern = "localhost|127\.0\.0\.1|::1|ShellExecute|XMLHttpRequest|fetch\(|WebSocket|EventSource|WpsHighSchoolMathEditorHost"
$scanFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:ProbeRoot "src") -Recurse -File) +
    @(Get-Item -LiteralPath (Join-Path $script:ProbeRoot "probe-manifest.json"))
$forbiddenHits = @()
foreach ($scanFile in $scanFiles) {
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($scanFile.FullName, [Text.Encoding]::UTF8)) {
        $lineNumber += 1
        if ($line -match $forbiddenPattern) {
            $forbiddenHits += "$($scanFile.FullName):${lineNumber}:$line"
        }
    }
}
if ($forbiddenHits.Count -gt 0) {
    throw "Packaged task-pane probe contains forbidden runtime text: $($forbiddenHits -join [Environment]::NewLine)"
}
Write-Host "Packaged task-pane probe validation passed ($Mode)."
