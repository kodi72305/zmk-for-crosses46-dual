[CmdletBinding()]
param(
    [switch]$SkipUpdate
)

$ErrorActionPreference = 'Stop'

function Invoke-West {
    param(
        [string[]]$Arguments
    )

    Write-Host "west $($Arguments -join ' ')" -ForegroundColor Cyan
    & west @Arguments
}

if (-not (Get-Command west -ErrorAction SilentlyContinue)) {
    throw "west command not found. Install it via 'pip install west' before running this script."
}

$defaultSdkPath = "D:\Downloads\zephyr-sdk-1.0.0-beta1"
if (-not $env:ZEPHYR_TOOLCHAIN_VARIANT) {
    $env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
}
if (-not $env:ZEPHYR_SDK_INSTALL_DIR) {
    if (-not (Test-Path -LiteralPath $defaultSdkPath)) {
        throw "Zephyr SDK path '$defaultSdkPath' not found. Install the SDK there or set ZEPHYR_SDK_INSTALL_DIR manually."
    }
    $env:ZEPHYR_SDK_INSTALL_DIR = (Resolve-Path -LiteralPath $defaultSdkPath).Path
}

$cmakeConfig = Join-Path $env:ZEPHYR_SDK_INSTALL_DIR "cmake/Zephyr-sdkConfig.cmake"
if (-not (Test-Path -LiteralPath $cmakeConfig)) {
    throw "Zephyr SDK at '$($env:ZEPHYR_SDK_INSTALL_DIR)' doesn't look valid (missing cmake/Zephyr-sdkConfig.cmake). Install Zephyr SDK 0.16.x+ and rerun."
}
Write-Host "Using Zephyr SDK at: $($env:ZEPHYR_SDK_INSTALL_DIR)" -ForegroundColor Yellow

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $repoRoot

try {
    $westDir = Join-Path $repoRoot ".west"
    if (-not (Test-Path (Join-Path $westDir "config"))) {
        Invoke-West -Arguments @("init", "-l", "config")
    }

    if (-not $SkipUpdate) {
        Invoke-West -Arguments @("update")
    }

    Invoke-West -Arguments @("zephyr-export")

    $builds = @(
        @{
            Name   = "crosses_left"
            Dir    = "build/crosses_left"
            Shield = "crosses_left"
            Extra  = @()
        },
        @{
            Name   = "crosses_right"
            Dir    = "build/crosses_right"
            Shield = "crosses_right"
            Extra  = @(
                "-DSNIPPET=studio-rpc-usb-uart",
                "-DCONFIG_ZMK_STUDIO=y"
            )
        }
    )

    foreach ($build in $builds) {
        $buildDir = Join-Path $repoRoot $build.Dir
        if (-not (Test-Path $buildDir)) {
            New-Item -ItemType Directory -Path $buildDir | Out-Null
        }

        $args = @(
            "build",
            "-p",
            "-d", $buildDir,
            "-b", "nice_nano_v2",
            "zmk/app",
            "--",
            "-DSHIELD=$($build.Shield)"
        ) + $build.Extra

        Invoke-West -Arguments $args

        $artifact = Join-Path $buildDir "zephyr/zmk.uf2"
        if (Test-Path $artifact) {
            Write-Host "✓ $($build.Name) firmware ready: $artifact" -ForegroundColor Green
        }
    }
}
finally {
    Pop-Location
}
