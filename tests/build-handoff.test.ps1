$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$handoffPath = Join-Path $projectRoot "scripts\build-handoff.ps1"
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($handoffPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$definition = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Get-HsmGitFileList"
}, $true)
if (-not $definition) { throw "Get-HsmGitFileList was not found in build-handoff.ps1." }
Invoke-Expression $definition.Extent.Text

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Output "build-handoff git file-list tests skipped (git is not installed)"
    return
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("hsm-handoff-list-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $testRoot "docs") -Force | Out-Null
try {
    $utf8 = New-Object Text.UTF8Encoding($false)
    $chineseName = ([char]0x6570).ToString() + ([char]0x5B66).ToString() + ([char]0x793A).ToString() + ([char]0x4F8B).ToString() + ".txt"
    [IO.File]::WriteAllText((Join-Path $testRoot ("docs\" + $chineseName)), "tracked", $utf8)
    [IO.File]::WriteAllText((Join-Path $testRoot "README.md"), "tracked", $utf8)
    & $git.Source -C $testRoot init -q
    & $git.Source -C $testRoot -c core.autocrlf=false add -A
    if ($LASTEXITCODE -ne 0) { throw "git add failed in the handoff fixture." }
    [IO.File]::WriteAllText((Join-Path $testRoot "docs\untracked.txt"), "untracked", $utf8)

    $tracked = @(Get-HsmGitFileList -GitPath $git.Source -Root $testRoot)
    if ($tracked -notcontains ("docs/" + $chineseName) -or $tracked -notcontains "README.md" -or $tracked.Count -ne 2) {
        throw "Tracked file list did not return Chinese paths verbatim: $($tracked -join ' | ')"
    }
    $untracked = @(Get-HsmGitFileList -GitPath $git.Source -Root $testRoot -Arguments @("ls-files", "--others", "--exclude-standard"))
    if (($untracked -join "|") -ne "docs/untracked.txt") {
        throw "Untracked file list is incorrect: $($untracked -join ' | ')"
    }
    Write-Output "build-handoff git file-list tests passed"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
