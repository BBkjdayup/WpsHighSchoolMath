param([string]$FixtureFile, [string]$CrashPoint)
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot "scripts\offline-install.ps1"
. (Join-Path $projectRoot "scripts\payload-integrity.ps1")

. (Join-Path $projectRoot "scripts\addin-maintenance.ps1")
$requiredFunctions = @(
    "Save-XmlDocument",
    "Set-ObjectPropertyValue",
    "Update-AuthorizationCache",
    "Update-HsmPublishRegistration",
    "Test-HsmInstalledState",
    "Invoke-HsmInstallTransaction"
)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$definitions = @(
    $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $requiredFunctions -contains $node.Name
    }, $true)
)
if ($definitions.Count -ne $requiredFunctions.Count) {
    throw "Could not load all install-transaction functions."
}
Invoke-Expression (($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")

function Write-TestFile {
    param([string]$Path, [string]$Content)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function New-TestPayload {
    param([string]$Path, [string]$HostType, [string]$PluginName)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    if ($HostType -eq "wps") {
        $hostMarker = "writer"
        $main = "load('js/ribbon.js');"
        $tabId = "mathTeacherTab"
    } else {
        $hostMarker = "presentation"
        $main = "load('js/ppt-api.js'); load('js/ribbon-ppt.js');"
        $tabId = "mathTeacherPptTab"
    }
    Write-TestFile (Join-Path $Path "index.html") ('<script>window.HSM_ENTRY_HOST = "' + $hostMarker + '";</script>')
    Write-TestFile (Join-Path $Path "main.js") $main
    Write-TestFile (Join-Path $Path "manifest.xml") ("<JsPlugin><Name>$PluginName</Name></JsPlugin>")
    Write-TestFile (Join-Path $Path "ribbon.xml") ('<customUI><ribbon><tabs><tab id="{0}" label="高中数学" /></tabs></ribbon></customUI>' -f $tabId)
    Write-TestFile (Join-Path $Path "runtime\WpsHighSchoolMathEditorHost.exe") "host"
}

function New-TransactionFixture {
    param([string]$Root)

    $installerRoot = Join-Path $Root "installer"
    $jsAddonsPath = Join-Path $Root "jsaddons"
    New-Item -ItemType Directory -Path $installerRoot, $jsAddonsPath -Force | Out-Null
    foreach ($control in @("uninstall.ps1", "uninstall-cleanup.ps1", "uninstall-registration.ps1", "addin-maintenance.ps1")) {
        Write-TestFile (Join-Path $installerRoot $control) "# fixture $control"
    }
    $writerFolder = "WpsHighSchoolMath_0.9.0"
    $pptFolder = "WpsHighSchoolMathPpt_0.9.0"
    $writerPayload = Join-Path $installerRoot "payload\$writerFolder"
    $pptPayload = Join-Path $installerRoot "payload\$pptFolder"
    New-TestPayload $writerPayload "wps" "WpsHighSchoolMath"
    New-TestPayload $pptPayload "wpp" "WpsHighSchoolMathPpt"
    $writerManifest = New-HsmPayloadManifest $writerPayload "WpsHighSchoolMath" "WpsHighSchoolMath" "0.9.0" "wps"
    $pptManifest = New-HsmPayloadManifest $pptPayload "WpsHighSchoolMath" "WpsHighSchoolMathPpt" "0.9.0" "wpp"

    $oldWriter = Join-Path $jsAddonsPath "WpsHighSchoolMath_0.8.1"
    $oldPpt = Join-Path $jsAddonsPath "WpsHighSchoolMathPpt_0.8.1"
    Write-TestFile (Join-Path $oldWriter "old.txt") "old-writer"
    Write-TestFile (Join-Path $oldPpt "old.txt") "old-ppt"

    $publishPath = Join-Path $jsAddonsPath "publish.xml"
    Write-TestFile (Join-Path $jsAddonsPath "WpsHighSchoolMath_Notes_1.0.0\manifest.xml") "<JsPlugin><Name>WpsHighSchoolMath_Notes</Name></JsPlugin>"
    Write-TestFile (Join-Path $jsAddonsPath "WpsHighSchoolMath_Notes_1.0.0\notes.txt") "independent plugin data"
    Write-TestFile (Join-Path $jsAddonsPath "WpsHighSchoolMath_8.8.8\manifest.xml") "<JsPlugin><Name>DifferentProduct</Name></JsPlugin>"
    Write-TestFile $publishPath @'
<jsplugins>
  <jsplugin name="WpsHighSchoolMath_Notes" type="wps" url="WpsHighSchoolMath_Notes_1.0.0" version="1.0.0" />
  <jsplugin name="OtherPlugin" type="wps" url="OtherPlugin_1.0" version="1.0" enable="enable_dev" />
  <jsplugin name="WpsHighSchoolMath" type="wps" url="WpsHighSchoolMath_0.8.1" version="0.8.1" enable="enable_dev" />
  <jsplugin name="WpsHighSchoolMathPpt" type="wpp" url="WpsHighSchoolMathPpt_0.8.1" version="0.8.1" enable="enable_dev" />
</jsplugins>
'@
    $authorizationPath = Join-Path $jsAddonsPath "authaddin.json"
    $authorization = [ordered]@{
        wps = [ordered]@{
            namelist = "old-writer;other"
            "old-writer" = [ordered]@{ name = "WpsHighSchoolMath"; path = $oldWriter; mode = 1; md5 = "old" }
            other = [ordered]@{ name = "OtherPlugin"; path = "C:/other"; mode = 1; md5 = "keep" }
        }
        wpp = [ordered]@{
            namelist = "old-ppt"
            "old-ppt" = [ordered]@{ name = "WpsHighSchoolMathPpt"; path = $oldPpt; mode = 1; md5 = "old" }
        }
    }
    Write-TestFile $authorizationPath ($authorization | ConvertTo-Json -Depth 8)

    return [pscustomobject]@{
        InstallerRoot = $installerRoot
        JsAddonsPath = $jsAddonsPath
        PublishPath = $publishPath
        AuthorizationPath = $authorizationPath
        OldWriter = $oldWriter
        OldPpt = $oldPpt
        WriterFolder = $writerFolder
        PptFolder = $pptFolder
        Plugins = @(
            @{ Name = "WpsHighSchoolMath"; Type = "wps"; FolderName = $writerFolder; ManifestSha256 = $writerManifest.Sha256 },
            @{ Name = "WpsHighSchoolMathPpt"; Type = "wpp"; FolderName = $pptFolder; ManifestSha256 = $pptManifest.Sha256 }
        )
    }
}

function Invoke-FixtureInstall {
    param([object]$Fixture, [scriptblock]$Checkpoint, [scriptblock]$Register)
    return @(Invoke-HsmInstallTransaction `
        -InstallerRoot $Fixture.InstallerRoot `
        -JsAddonsPath $Fixture.JsAddonsPath `
        -PublishPath $Fixture.PublishPath `
        -AuthorizationPath $Fixture.AuthorizationPath `
        -Plugins $Fixture.Plugins `
        -StaleNames @("WpsHighSchoolMath", "WpsHighSchoolMathE2E3", "WpsHighSchoolMathPpt") `
        -Product "WpsHighSchoolMath" `
        -Version "0.9.0" `
        -TestCheckpoint $Checkpoint `
        -RegisterUninstaller $Register)
}

if ($FixtureFile) {
    $fixture = Import-Clixml -LiteralPath $FixtureFile
    $register = if ($CrashPoint -eq "after-register") { { param($v, $source, $root) } }
    Invoke-FixtureInstall $fixture { param($p) if ($p -eq $CrashPoint) { [Environment]::Exit(72) } } $register | Out-Null
    throw "Checkpoint was not reached: $CrashPoint"
}

function Invoke-CrashInstall($Fixture, $Point) {
    $data = Join-Path $Fixture.InstallerRoot "fixture.clixml"
    $Fixture | Export-Clixml -LiteralPath $data
    & (Join-Path $PSHOME "powershell.exe") -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -FixtureFile $data -CrashPoint $Point
    if ($LASTEXITCODE -ne 72) { throw "Install child did not exit at $Point" }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("hsmt-" + [Guid]::NewGuid().ToString("N").Substring(0,10))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $success = New-TransactionFixture (Join-Path $testRoot "success")
    $results = @(Invoke-FixtureInstall $success $null)
    if ($results.Count -ne 2 -or
        -not (Test-Path -LiteralPath (Join-Path $success.JsAddonsPath $success.WriterFolder)) -or
        -not (Test-Path -LiteralPath (Join-Path $success.JsAddonsPath $success.PptFolder)) -or
        (Test-Path -LiteralPath $success.OldWriter) -or
        (Test-Path -LiteralPath $success.OldPpt)) {
        throw "Successful transaction did not commit both payloads together."
    }
    [xml]$successPublish = Get-Content -LiteralPath $success.PublishPath -Raw -Encoding UTF8
    if (-not $successPublish.DocumentElement.SelectSingleNode("*[@name='WpsHighSchoolMath_Notes' and @url='WpsHighSchoolMath_Notes_1.0.0']") -or
        [IO.File]::ReadAllText((Join-Path $success.JsAddonsPath "WpsHighSchoolMath_Notes_1.0.0\notes.txt")) -ne "independent plugin data") {
        throw "Install changed the registration or data of an independent add-in with a shared prefix."
    }
    if (@($successPublish.DocumentElement.SelectNodes("*[@name='OtherPlugin']")).Count -ne 1) {
        throw "Successful transaction changed an unrelated publish.xml entry."
    }
    $successAuth = Get-Content -LiteralPath $success.AuthorizationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($successAuth.wps.other.md5 -ne "keep") {
        throw "Successful transaction changed an unrelated authorization entry."
    }

    foreach ($failurePoint in @("before-stage-copy-wpp", "after-stage", "after-backup", "after-payload-switch-1", "after-payload-switch-2", "after-auth", "after-publish", "after-validate")) {
        $failure = New-TransactionFixture (Join-Path $testRoot $failurePoint)
        $publishHashBefore = Get-HsmSha256 $failure.PublishPath
        $authHashBefore = Get-HsmSha256 $failure.AuthorizationPath
        $caught = $false
        try {
            [void](Invoke-FixtureInstall $failure { param($point) if ($point -eq $failurePoint) { throw "injected-$failurePoint" } })
        } catch {
            if ($_.Exception.Message -notmatch [regex]::Escape("injected-$failurePoint") -or $_.Exception.Message -match "Rollback also failed") { throw }
            $caught = $true
        }
        if (-not $caught) { throw "Injected failure $failurePoint did not fail the transaction." }
        if (-not (Test-Path -LiteralPath (Join-Path $failure.OldWriter "old.txt")) -or
            -not (Test-Path -LiteralPath (Join-Path $failure.OldPpt "old.txt")) -or
            (Test-Path -LiteralPath (Join-Path $failure.JsAddonsPath $failure.WriterFolder)) -or
            (Test-Path -LiteralPath (Join-Path $failure.JsAddonsPath $failure.PptFolder)) -or
            (Get-HsmSha256 $failure.PublishPath) -ne $publishHashBefore -or
            (Get-HsmSha256 $failure.AuthorizationPath) -ne $authHashBefore) {
            throw "Transaction failure $failurePoint did not restore the previous installation byte-for-byte."
        }
        if (@(Get-ChildItem -LiteralPath $failure.JsAddonsPath -Directory -Filter ".hsm-install-*").Count -ne 0) {
            throw "Successful rollback left a transaction directory behind for $failurePoint."
        }
    }

    foreach ($foreign in @("WpsHighSchoolMath_Notes_1.0.0", "WpsHighSchoolMath_8.8.8")) {
        if (-not [IO.File]::Exists((Join-Path $success.JsAddonsPath ($foreign + "\manifest.xml")))) { throw "Deleted a foreign add-in: $foreign" }
    }
    foreach ($checkpoint in @("after-backup","after-payload-switch-1","after-publish","after-register")) {
        $crash = New-TransactionFixture (Join-Path $testRoot ("crash-" + $checkpoint))
        Invoke-CrashInstall $crash $checkpoint
        [xml]$published = [IO.File]::ReadAllText($crash.PublishPath)
        foreach ($node in $published.DocumentElement.SelectNodes("*[@name='WpsHighSchoolMath' or @name='WpsHighSchoolMathPpt']")) {
            if (-not [IO.Directory]::Exists((Join-Path $crash.JsAddonsPath $node.GetAttribute("url")))) { throw "Registered host unavailable at $checkpoint" }
        }
        if ($checkpoint -eq "after-publish") {
            $extra = $published.CreateElement("jsplugin")
            $extra.SetAttribute("name", "RegisteredDuringInterruption")
            [void]$published.DocumentElement.AppendChild($extra)
            $published.Save($crash.PublishPath)
        }
        $marker = Join-Path $crash.InstallerRoot "replayed"
        $register = { param($v, $source, $root)
            if ($source -like "*\control" -and [IO.File]::Exists((Join-Path $source "uninstall.ps1"))) { [IO.File]::WriteAllText($marker, $v) }
        }
        [void](Invoke-FixtureInstall $crash $null $register)
        if (@(Get-ChildItem -LiteralPath $crash.JsAddonsPath -Directory -Filter ".hsm-*").Count) { throw "Orphan transaction after $checkpoint" }
        if ($checkpoint -eq "after-register" -and -not [IO.File]::Exists($marker)) { throw "Interrupted registration was not replayed." }
        if ($checkpoint -eq "after-publish" -and -not [IO.File]::ReadAllText($crash.PublishPath).Contains("RegisteredDuringInterruption")) { throw "Lost a concurrent third-party registration." }
    }
    $legacy = New-TransactionFixture (Join-Path $testRoot "legacy")
    $legacyTx = Join-Path $legacy.JsAddonsPath ".hsm-install-0123456789ab"
    $payloadBackup = Join-Path $legacyTx "backup\payloads"
    [void][IO.Directory]::CreateDirectory($payloadBackup)
    Copy-Item -LiteralPath $legacy.PublishPath -Destination (Join-Path $legacyTx "backup\publish.xml")
    foreach ($oldPath in @($legacy.OldWriter, $legacy.OldPpt)) {
        $old = Get-Item -LiteralPath $oldPath
        if ($old.Parent.FullName -ne $legacy.JsAddonsPath) { throw "Invalid legacy fixture" }
        [IO.Directory]::Move($old.FullName, (Join-Path $payloadBackup $old.Name))
    }
    Repair-HsmPendingTransactions $legacy.JsAddonsPath @("WpsHighSchoolMath","WpsHighSchoolMathPpt")
    if (-not [IO.Directory]::Exists($legacy.OldWriter) -or -not [IO.Directory]::Exists($legacy.OldPpt) -or [IO.Directory]::Exists($legacyTx)) {
        throw "Did not restore legacy 0.9.0 interrupted backups."
    }
    $same = New-TransactionFixture (Join-Path $testRoot "repair")
    [void](Invoke-FixtureInstall $same $null)
    $damaged = Join-Path $same.JsAddonsPath ($same.WriterFolder + "\main.js")
    Write-TestFile $damaged "previous damaged payload"
    Invoke-CrashInstall $same "after-displace-wps"
    Repair-HsmPendingTransactions $same.JsAddonsPath @("WpsHighSchoolMath","WpsHighSchoolMathPpt")
    if ([IO.File]::ReadAllText($damaged) -ne "previous damaged payload") { throw "Interrupted same-version repair lost the old folder." }
    [void](Invoke-FixtureInstall $same $null)
    if ([IO.File]::ReadAllText($damaged) -eq "previous damaged payload") { throw "Retry did not repair the damaged payload." }

    $windowsFailure = New-TransactionFixture (Join-Path $testRoot "windows")
    $originalList = @(Get-ChildItem -LiteralPath $windowsFailure.JsAddonsPath -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName + (Get-HsmSha256 $_.FullName) })
    try {
        [void](Invoke-FixtureInstall $windowsFailure $null { throw "injected registry error" })
        throw "Missing Windows uninstall registration failure."
    } catch { if ($_.Exception.Message -notlike "*injected registry error*") { throw } }
    $restoredList = @(Get-ChildItem -LiteralPath $windowsFailure.JsAddonsPath -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName + (Get-HsmSha256 $_.FullName) })
    if (Compare-Object $originalList $restoredList) { throw "Windows registration failure changed WPS installation state." }

    # Reinstall the already committed version. Check every existing file after both staged and partial failures.
    $previousHashes = @{}
    foreach ($file in Get-ChildItem -LiteralPath $success.JsAddonsPath -Recurse -File) {
        $previousHashes[$file.FullName] = Get-HsmSha256 $file.FullName
    }
    foreach ($failurePoint in @("before-stage-copy-wpp", "after-stage", "after-payload-switch-1", "after-publish", "corrupt-source")) {
        if ($failurePoint -eq "corrupt-source") {
            Write-TestFile (Join-Path $success.InstallerRoot "payload\$($success.PptFolder)\main.js") "incomplete"
        }
        $caught = $false
        try {
            [void](Invoke-FixtureInstall $success { param($point) if ($point -eq $failurePoint) { throw "injected-$point" } })
        } catch {
            if ($_.Exception.Message -match "Rollback also failed") { throw }
            $caught = $true
        }
        if (-not $caught) { throw "Same-version fault was ignored: $failurePoint" }
        foreach ($path in $previousHashes.Keys) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-HsmSha256 $path) -ne $previousHashes[$path]) {
                throw "Same-version rollback changed $path at $failurePoint"
            }
        }
        if (@(Get-ChildItem -LiteralPath $success.JsAddonsPath -Recurse -File).Count -ne $previousHashes.Count) {
            throw "Unexpected files after reinstall rollback"
        }
    }

    Write-Output "offline install transaction tests passed"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
