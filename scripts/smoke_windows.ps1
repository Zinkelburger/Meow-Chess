# Run the installed release executable with disposable app data and wait for
# its native window. This catches missing DLLs/plugin startup failures that an
# installer file-list check cannot. Only the process started here is stopped.
param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$dataDir = Join-Path ([System.IO.Path]::GetTempPath()) ('meow-smoke-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $dataDir | Out-Null
$previousData = $env:MEOW_DATA_DIR
$previousSetup = $env:MEOW_CHESS_DESKTOP_SETUP
$app = $null
try {
    $env:MEOW_DATA_DIR = $dataDir
    $env:MEOW_CHESS_DESKTOP_SETUP = '0'
    $app = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
    $deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 250
        $app.Refresh()
        if ($app.HasExited) { throw "Installed app exited before opening a window: $($app.ExitCode)" }
    } while ($app.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline)
    if ($app.MainWindowHandle -eq 0) { throw 'Installed app did not create a window within 30 seconds' }
    Start-Sleep -Seconds 3
    $app.Refresh()
    if ($app.HasExited) { throw 'Installed app exited during startup' }
    if (-not $app.CloseMainWindow()) { throw 'Installed app refused a normal window close' }
    if (-not $app.WaitForExit(10000)) { throw 'Installed app did not close within 10 seconds' }
    if ($app.ExitCode -ne 0) { throw "Installed app exit code: $($app.ExitCode)" }
    Write-Host 'PASS: installed release opened its native window and closed normally.'
} finally {
    if ($null -ne $app) {
        if (-not $app.HasExited) { $app.Kill(); $app.WaitForExit(10000) | Out-Null }
        $app.Dispose()
    }
    $env:MEOW_DATA_DIR = $previousData
    $env:MEOW_CHESS_DESKTOP_SETUP = $previousSetup
    Remove-Item -LiteralPath $dataDir -Recurse -Force
}
