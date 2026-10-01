[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$RestartArmouryProcesses,
    [switch]$ApplyWinHttpBypass
)

$ErrorActionPreference = 'Stop'
$noProxy = 'localhost,127.0.0.1,::1'
$bypass = 'localhost;127.*;[::1];<local>'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($PSCmdlet.ShouldProcess('current user environment', "Set NO_PROXY and no_proxy to $noProxy")) {
    [Environment]::SetEnvironmentVariable('NO_PROXY', $noProxy, 'User')
    [Environment]::SetEnvironmentVariable('no_proxy', $noProxy, 'User')
    $env:NO_PROXY = $noProxy
    $env:no_proxy = $noProxy
    Write-Host "User NO_PROXY/no_proxy set to $noProxy"
}

if ($ApplyWinHttpBypass) {
    if (-not (Test-IsAdministrator)) {
        throw 'ApplyWinHttpBypass requires an elevated PowerShell window.'
    }
    if ($PSCmdlet.ShouldProcess('WinHTTP', "Set proxy bypass list to $bypass")) {
        & netsh winhttp set proxy proxy-server='127.0.0.1:7897' bypass-list=$bypass
        if ($LASTEXITCODE -ne 0) {
            throw "netsh failed with exit code $LASTEXITCODE"
        }
    }
}

if ($RestartArmouryProcesses) {
    $names = 'asus_framework', 'ArmourySocketServer', 'ArmouryHtmlDebugServer', 'ArmourySwAgent'
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -in $names)
    foreach ($process in $processes) {
        if ($PSCmdlet.ShouldProcess("$($process.ProcessName) [$($process.Id)]", 'Stop user-mode Armoury process')) {
            Stop-Process -Id $process.Id -Force
        }
    }
    Start-Sleep -Seconds 2

    $socket = Join-Path ${env:ProgramFiles(x86)} 'ASUS\ArmouryDevice\dll\ArmourySocketServer\ArmourySocketServer.exe'
    if (Test-Path -LiteralPath $socket) {
        if ($PSCmdlet.ShouldProcess($socket, 'Start ArmourySocketServer with NO_PROXY')) {
            Start-Process -FilePath $socket -WorkingDirectory (Split-Path $socket) -WindowStyle Hidden | Out-Null
        }
    } else {
        Write-Warning "ArmourySocketServer was not found at $socket"
    }
}

Write-Host 'Next: reopen Armoury Crate and check the Devices page.'
Write-Host 'This script never flashes firmware, removes drivers, changes BIOS, or reboots Windows.'
