# Take the setup through the life a TD's copy has: install it (over the
# previous release when one is given, so the upgrade path is what is tested),
# check the files, the .meow association and that the old bundle left nothing
# behind, launch it, refuse to uninstall while it is open, then uninstall and
# check that the app and its registry entries are gone while tournament data
# stays.
#
# This is the real per-user install, so it refuses to run where Meow Chess is
# already installed: use a CI runner, a VM or a spare Windows account. Runs
# under Windows PowerShell 5.1 as well as pwsh, so a stock Windows 10 can run
#
#   powershell -ExecutionPolicy Bypass -File scripts\test_windows_installer.ps1 -Setup <setup.exe>
param(
    [Parameter(Mandatory=$true)][string]$Setup,
    [string]$PreviousSetup = '',
    [string]$ExpectedVersion = ''
)
$ErrorActionPreference = 'Stop'

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{CD658FF7-A9DD-4ECA-9E13-9E8F07BABCEF}_is1'
if (Test-Path $uninstallKey) {
    throw 'Meow Chess is already installed for this user; this test would replace and then remove it. Use a clean Windows account or VM.'
}

$Setup = (Resolve-Path $Setup).Path
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('meow-installer-test-' + [guid]::NewGuid())
$installDir = Join-Path $work 'Meow Chess'
$appData = Join-Path $work 'library'
$logs = Join-Path $work 'logs'
$exe = Join-Path $installDir 'meow_chess.exe'
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Meow Chess.lnk'
New-Item -ItemType Directory -Path $appData, $logs | Out-Null

# The real library folder (windows/runner/Runner.rc names it). Only the
# sentinel is written there, and only if it was not already present.
$libraryRoot = Join-Path $env:APPDATA 'org.meowchess'
$library = Join-Path $libraryRoot 'Meow Chess'
$sentinel = Join-Path $library 'installer-test-sentinel.txt'
$createdLibraryRoot = -not (Test-Path $libraryRoot)
$previousData = $env:MEOW_DATA_DIR
$previousSetupEnv = $env:MEOW_CHESS_DESKTOP_SETUP
$app = $null

function Invoke-Setup([string]$Executable, [string]$Label) {
    $log = Join-Path $logs "$Label.log"
    # Start-Process -Wait: setup.exe is a GUI program, so the call operator
    # would return before it finished.
    $proc = Start-Process -FilePath $Executable -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
        ('/DIR="{0}"' -f $installDir), ('/LOG="{0}"' -f $log)
    )
    if ($proc.ExitCode -ne 0) {
        if (Test-Path $log) { Get-Content $log -Tail 80 }
        throw "$Label setup exited with $($proc.ExitCode)"
    }
    Write-Host "PASS: $Label setup installed into $installDir"
}

# The uninstaller hands over to a copy of itself in %TEMP%, which may still be
# deleting the folder when the exit code arrives; callers wait for the result.
function Invoke-Uninstall([string]$Label) {
    $log = Join-Path $logs "$Label.log"
    $proc = Start-Process -FilePath (Join-Path $installDir 'unins000.exe') -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="{0}"' -f $log)
    )
    return $proc.ExitCode
}

function Get-DefaultValue([string]$Key) {
    if (-not (Test-Path -LiteralPath $Key)) { return $null }
    return (Get-ItemProperty -LiteralPath $Key).'(default)'
}

function Start-App {
    $started = Start-Process -FilePath $exe -WorkingDirectory $installDir -PassThru
    $deadline = (Get-Date).AddSeconds(30)
    while ($started.MainWindowHandle -eq 0) {
        if ($started.HasExited) { throw "Installed app exited before opening a window: $($started.ExitCode)" }
        if ((Get-Date) -gt $deadline) { throw 'Installed app did not create a window within 30 seconds' }
        Start-Sleep -Milliseconds 250
        $started.Refresh()
    }
    return $started
}

function Wait-Until([scriptblock]$Condition, [string]$Failure) {
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (& $Condition)) {
        if ((Get-Date) -gt $deadline) { throw $Failure }
        Start-Sleep -Milliseconds 250
    }
}

try {
    # The smoke test and the open-app check use a disposable library and do
    # not touch the association themselves.
    $env:MEOW_DATA_DIR = $appData
    $env:MEOW_CHESS_DESKTOP_SETUP = '0'
    if (-not (Test-Path $sentinel)) {
        New-Item -ItemType Directory -Path $library -Force | Out-Null
        Set-Content -LiteralPath $sentinel -Value 'Left by test_windows_installer.ps1; uninstall must keep it.'
    }

    if ($PreviousSetup) {
        Invoke-Setup (Resolve-Path $PreviousSetup).Path 'previous'
    } else {
        Write-Host 'No previous release given: testing a reinstall over this setup.'
        Invoke-Setup $Setup 'first'
    }
    # Files a newer bundle no longer ships must not survive the upgrade.
    $stale = @(
        (Join-Path $installDir 'data\flutter_assets\retired-asset.txt'),
        (Join-Path $installDir 'retired_plugin.dll')
    )
    foreach ($f in $stale) { Set-Content -LiteralPath $f -Value 'stale' }
    Invoke-Setup $Setup 'upgrade'

    foreach ($f in @('meow_chess.exe', 'VCRUNTIME140.dll', 'unins000.exe', 'data\flutter_assets\AssetManifest.bin')) {
        if (-not (Test-Path (Join-Path $installDir $f))) { throw "Installed app is missing $f" }
    }
    foreach ($f in $stale) {
        if (Test-Path -LiteralPath $f) { throw "Upgrade left a stale file behind: $f" }
    }
    if (-not (Test-Path -LiteralPath $shortcut)) { throw "No Start menu shortcut at $shortcut" }
    if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Meow Chess')) {
        throw 'The old Start menu folder survived the upgrade'
    }

    $entry = Get-ItemProperty -LiteralPath $uninstallKey
    if ($entry.DisplayName -ne 'Meow Chess') { throw "Settings > Apps lists '$($entry.DisplayName)'" }
    if ($ExpectedVersion) {
        if ($entry.DisplayVersion -ne $ExpectedVersion) { throw "Settings > Apps shows version '$($entry.DisplayVersion)'" }
        $numeric = [version]($ExpectedVersion.Split('-')[0])
        $info = (Get-Item -LiteralPath $Setup).VersionInfo
        if ($info.FileMajorPart -ne $numeric.Major -or $info.FileMinorPart -ne $numeric.Minor -or $info.FileBuildPart -ne $numeric.Build) {
            throw "Setup file version is $($info.FileVersion), expected $numeric"
        }
    }

    $progId = Get-DefaultValue 'HKCU:\Software\Classes\.meow'
    if ($progId -ne 'MeowChess.Tournament') { throw ".meow is registered to '$progId'" }
    $command = Get-DefaultValue 'HKCU:\Software\Classes\MeowChess.Tournament\shell\open\command'
    if ($command -notlike '*meow_chess.exe*%1*') { throw "Unexpected open command: $command" }
    $choice = (Get-ItemProperty 'HKCU:\Software\MeowChess').FileAssociationChoice
    if ($choice -ne 'yes') { throw 'Installer did not record the association choice' }
    Write-Host "PASS: files, shortcut, Settings entry and .meow association ($command)"

    & (Join-Path $PSScriptRoot 'smoke_windows.ps1') -Executable $exe

    $app = Start-App
    $code = Invoke-Uninstall 'uninstall-while-open'
    Start-Sleep -Seconds 2
    if (-not (Test-Path $exe) -or -not (Test-Path $uninstallKey)) {
        throw "Uninstall went ahead while the app was open (exit $code)"
    }
    Write-Host "PASS: uninstall stopped while the app was open (exit $code)"
    if (-not $app.CloseMainWindow()) { throw 'Installed app refused a normal window close' }
    if (-not $app.WaitForExit(10000)) { throw 'Installed app did not close within 10 seconds' }

    $code = Invoke-Uninstall 'uninstall'
    if ($code -ne 0) {
        Get-Content (Join-Path $logs 'uninstall.log') -Tail 80
        throw "Uninstaller exited with $code"
    }
    Wait-Until { -not (Test-Path $installDir) } "Uninstall left $installDir behind"
    foreach ($key in @(
        $uninstallKey,
        'HKCU:\Software\MeowChess',
        'HKCU:\Software\Classes\MeowChess.Tournament',
        'HKCU:\Software\Classes\Applications\meow_chess.exe',
        'HKCU:\Software\Classes\.meow'
    )) {
        if (Test-Path -LiteralPath $key) { throw "Uninstall left $key behind" }
    }
    if (Test-Path -LiteralPath $shortcut) { throw 'Uninstall left the Start menu shortcut' }
    if (-not (Test-Path -LiteralPath $sentinel)) { throw 'Uninstall removed the tournament library' }
    Write-Host 'PASS: uninstall removed the app, shortcut and registry entries and kept the library'
} finally {
    if ($null -ne $app) {
        if (-not $app.HasExited) { $app.Kill(); $app.WaitForExit(10000) | Out-Null }
        $app.Dispose()
    }
    # Leave the machine as it was, even after a failure.
    if ((Test-Path $uninstallKey) -and (Test-Path (Join-Path $installDir 'unins000.exe'))) {
        Invoke-Uninstall 'cleanup' | Out-Null
    }
    $env:MEOW_DATA_DIR = $previousData
    $env:MEOW_CHESS_DESKTOP_SETUP = $previousSetupEnv
    Remove-Item -LiteralPath $sentinel -ErrorAction SilentlyContinue
    if ($createdLibraryRoot) { Remove-Item -LiteralPath $libraryRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
