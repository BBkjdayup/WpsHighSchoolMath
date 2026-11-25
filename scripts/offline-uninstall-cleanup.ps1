param(
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [int]$ParentProcessId
)

$ErrorActionPreference = "Stop"

$programsRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs"))
$resolvedTarget = [IO.Path]::GetFullPath($TargetRoot)
if ([IO.Path]::GetDirectoryName($resolvedTarget) -ne $programsRoot -or
    [IO.Path]::GetFileName($resolvedTarget) -notmatch '^WpsHighSchoolMath-Uninstalling-[0-9a-f]{32}$' -or
    $resolvedTarget -ne [IO.Path]::GetFullPath($PSScriptRoot) -or
    ((Get-Item -LiteralPath $resolvedTarget -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "Refusing to remove an unexpected uninstall directory: $resolvedTarget"
}

if ($ParentProcessId -gt 0) {
    Wait-Process -Id $ParentProcessId -Timeout 15 -ErrorAction SilentlyContinue
}
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    if (-not (Test-Path -LiteralPath $resolvedTarget)) { break }
    try {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
