param(
    [string]$Destination,
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$SkipMarketing # Accepted for callers of earlier releases.
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$package = Get-Content -LiteralPath (Join-Path $projectRoot "package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$product = [string]$package.name
$version = [string]$package.version
$dateStamp = [DateTime]::Today.ToString("yyyyMMdd")

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $Destination = Join-Path $desktop "${product}-Handoff-${version}-${dateStamp}"
}
$destinationFull = [IO.Path]::GetFullPath($Destination)
$sourceRoot = Join-Path $destinationFull "01-source"
$releaseRoot = Join-Path $destinationFull "02-current-release"
$zipPath = "$destinationFull.zip"
$zipHashPath = "$zipPath.sha256"

function Assert-SafeNewDestination {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        throw "Destination already exists. Move or rename it before rebuilding: $Path"
    }
    $projectPrefix = $projectRoot.TrimEnd("\") + "\"
    if ($Path.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The handoff package must be created outside the project directory."
    }
}

function Copy-RequiredItem {
    param([string]$RelativePath)

    $source = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required handoff source is missing: $RelativePath"
    }
    $target = Join-Path $sourceRoot $RelativePath
    $targetParent = Split-Path -Parent $target
    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

function Invoke-ProjectScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments,
        [string]$Description
    )

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Remove-DirectoryInsideSource {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $sourcePrefix = [IO.Path]::GetFullPath($sourceRoot).TrimEnd("\") + "\"
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the handoff source: $fullPath"
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Assert-NoPrivateMaterial {
    $forbiddenNames = @(Get-ChildItem -LiteralPath $destinationFull -File -Recurse -Force | Where-Object {
        $_.Name -match '(?i)(ed25519-private|issuance-history)' -or
        $_.Extension -match '(?i)^\.(pem|key|pfx|p12)$'
    })
    if ($forbiddenNames.Count -gt 0) {
        throw "Private material was found in the handoff package: $($forbiddenNames.FullName -join ', ')"
    }
}

function Write-HashManifest {
    $manifestPath = Join-Path $destinationFull "SHA256SUMS.txt"
    $records = @(Get-ChildItem -LiteralPath $destinationFull -File -Recurse -Force |
        Where-Object { $_.FullName -ne $manifestPath } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($destinationFull.TrimEnd("\").Length + 1).Replace("\", "/")
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash  $relative"
        })
    [IO.File]::WriteAllLines($manifestPath, $records, (New-Object Text.UTF8Encoding($false)))
    return $records.Count
}

Assert-SafeNewDestination -Path $destinationFull
if (Test-Path -LiteralPath $zipPath) { throw "Archive already exists: $zipPath" }
if (Test-Path -LiteralPath $zipHashPath) { throw "Archive hash already exists: $zipHashPath" }

New-Item -ItemType Directory -Path $sourceRoot, $releaseRoot -Force | Out-Null

$rootFiles = @(
    ".gitattributes",
    ".gitignore",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CLAUDE.md",
    "HANDOFF.md",
    "README.md",
    "package.json",
    "index.html",
    "main.js",
    "manifest.xml",
    "ribbon.xml"
)
$sourceDirectories = @("js", "ppt", "probes", "scripts", "specs", "tests", "ui", "docs")
foreach ($path in $rootFiles + $sourceDirectories) {
    $requiredPath = Join-Path $projectRoot $path
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required handoff source is missing: $path"
    }
}

function Get-HsmGitFileList {
    <#
    .SYNOPSIS
    以 UTF-8 读取 git ls-files 的 NUL 分隔输出，关闭 core.quotepath，保证中文文件名原样返回。
    #>
    param(
        [Parameter(Mandatory = $true)][string]$GitPath,
        [Parameter(Mandatory = $true)][string]$Root,
        [string[]]$Arguments = @("ls-files")
    )

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $GitPath
    $startInfo.Arguments = "-C `"$Root`" -c core.quotepath=off " + ($Arguments -join " ") + " -z"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { return @() }
    } finally {
        $process.Dispose()
    }
    # PowerShell 5.1 会把 Split 的枚举参数误当作分隔符，改用 -split 并过滤空项
    return @($output -split "`0" | Where-Object { $_ })
}

$gitSourceCmd = Get-Command git -ErrorAction SilentlyContinue
$trackedEntries = @()
if ($gitSourceCmd -and (Test-Path -LiteralPath (Join-Path $projectRoot ".git"))) {
    $trackedEntries = @(Get-HsmGitFileList -GitPath $gitSourceCmd.Source -Root $projectRoot)
}

if ($trackedEntries.Count -gt 0) {
    # 优先按 Git 受控清单导出源码树，防止本地未跟踪目录或编译中间产物混入交接包
    $rootSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $rootFiles) { [void]$rootSet.Add($item) }
    $dirPrefixes = @($sourceDirectories | ForEach-Object { $_ + "/" })
    foreach ($entry in $trackedEntries) {
        $normalized = ([string]$entry).Replace("\", "/")
        $include = $rootSet.Contains($normalized)
        if (-not $include) {
            foreach ($prefix in $dirPrefixes) {
                if ($normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                    $include = $true
                    break
                }
            }
        }
        if ($include) {
            $relativePath = $normalized.Replace("/", "\")
            if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath))) {
                Write-Warning "跳过已在工作区删除、但仍在 Git 受控清单中的文件：$normalized"
                continue
            }
            Copy-RequiredItem -RelativePath $relativePath
        }
    }
    # 未加入 Git 的新文件不会进入交接包，提示维护者确认
    $untrackedEntries = @(Get-HsmGitFileList -GitPath $gitSourceCmd.Source -Root $projectRoot `
        -Arguments @("ls-files", "--others", "--exclude-standard"))
    foreach ($entry in $untrackedEntries) {
        $normalized = ([string]$entry).Replace("\", "/")
        if ($rootSet.Contains($normalized) -or @($dirPrefixes | Where-Object { $normalized.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count) {
            Write-Warning "未加入 Git 的文件不会进入交接包：$normalized"
        }
    }
} else {
    foreach ($path in $rootFiles + $sourceDirectories) {
        Copy-RequiredItem -RelativePath $path
    }
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force |
        Where-Object { $_.Extension -in @(".obj", ".lib", ".exp", ".pdb", ".log", ".tmp", ".bak") } |
        Remove-Item -Force
}

if (-not $SkipBuild) {
    Invoke-ProjectScript `
        -ScriptPath (Join-Path $sourceRoot "scripts\build-offline.ps1") `
        -Arguments @("-BuildMode", "Internal") `
        -Description "Internal offline build"
}

if (-not $SkipTests) {
    Invoke-ProjectScript `
        -ScriptPath (Join-Path $sourceRoot "scripts\run-tests.ps1") `
        -Arguments @() `
        -Description "Handoff source test suite"
}

$sourceRelease = Join-Path $sourceRoot "release"
$pluginArtifactNames = @(
    "${product}-${version}-offline.exe",
    "${product}-${version}-offline.zip",
    "${product}-${version}-checksums.sha256",
    "${product}-${version}-release-manifest.json"
)
foreach ($name in $pluginArtifactNames) {
    $path = Join-Path $sourceRelease $name
    if ($SkipBuild) { continue }
    Copy-Item -LiteralPath $path -Destination (Join-Path $releaseRoot $name) -ErrorAction Stop
}

Remove-DirectoryInsideSource -Path (Join-Path $sourceRoot "output")

Copy-Item -LiteralPath (Join-Path $sourceRoot "HANDOFF.md") -Destination (Join-Path $destinationFull "README-FIRST.md") -Force

Assert-NoPrivateMaterial

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($gitCommand) {
    & $gitCommand.Source -C $sourceRoot init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize the handoff Git repository." }
    & $gitCommand.Source -C $sourceRoot config user.name "Project Handoff"
    & $gitCommand.Source -C $sourceRoot config user.email "handoff@local.invalid"
    & $gitCommand.Source -C $sourceRoot add --all
    & $gitCommand.Source -C $sourceRoot commit -m "Initial handoff snapshot" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the handoff Git baseline commit." }
}

$manifestCount = Write-HashManifest

[IO.Compression.ZipFile]::CreateFromDirectory(
    $destinationFull,
    $zipPath,
    [IO.Compression.CompressionLevel]::Optimal,
    $true
)
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($zipHashPath, "$zipHash  $([IO.Path]::GetFileName($zipPath))`r`n", (New-Object Text.UTF8Encoding($false)))

$verifyRoot = Join-Path ([IO.Path]::GetTempPath()) ("hsm-handoff-verify-" + [Guid]::NewGuid().ToString("N"))
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $verifyRoot)
    $verifiedManifest = Get-ChildItem -LiteralPath $verifyRoot -File -Recurse -Filter "SHA256SUMS.txt" | Select-Object -First 1
    if (-not $verifiedManifest) { throw "The handoff archive does not contain SHA256SUMS.txt." }
    $verifiedRoot = Split-Path -Parent $verifiedManifest.FullName
    foreach ($line in Get-Content -LiteralPath $verifiedManifest.FullName -Encoding UTF8) {
        if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Invalid hash manifest line: $line" }
        $expected = $Matches[1]
        $relative = $Matches[2].Replace("/", "\")
        $filePath = Join-Path $verifiedRoot $relative
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "Archive file missing: $relative" }
        $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "Archive hash mismatch: $relative" }
    }
} finally {
    if (Test-Path -LiteralPath $verifyRoot) {
        Remove-Item -LiteralPath $verifyRoot -Recurse -Force
    }
}

Write-Output "Handoff package created and verified."
Write-Output "Directory: $destinationFull"
Write-Output "Archive: $zipPath"
Write-Output "Archive SHA256: $zipHash"
Write-Output "Manifest file count: $manifestCount"
