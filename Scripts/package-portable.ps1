$ErrorActionPreference = 'Stop'
$qRoot = Split-Path $PSScriptRoot -Parent
Push-Location $qRoot
try {
    $qBin = (& swift build --configuration release --show-bin-path).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate release products' }
    $qDestination = Join-Path $qRoot '.build/packages/q-windows-x64'
    if (Test-Path -LiteralPath $qDestination) { throw "Package directory already exists: $qDestination" }
    New-Item -ItemType Directory -Path $qDestination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $qBin 'q.exe') -Destination $qDestination

    # Swift's installed runtime directory includes the matching ICU and MSVC
    # redistributables. Copy runtime DLLs, never the compiler or developer SDK.
    $qRuntime = @($env:Path -split ';' | Where-Object {
        $_ -and (Test-Path -LiteralPath (Join-Path $_ 'swiftCore.dll'))
    } | Select-Object -Unique)
    if ($qRuntime.Count -ne 1) { throw "Expected exactly one Swift runtime directory, found $($qRuntime.Count)" }
    Get-ChildItem -LiteralPath $qRuntime[0] -Filter '*.dll' | Copy-Item -Destination $qDestination
    Get-ChildItem -LiteralPath $qBin -Filter '*.dll' | Copy-Item -Destination $qDestination -Force
    Copy-Item -LiteralPath 'Docs/PORTABLE_CLI.md' -Destination (Join-Path $qDestination 'README.md')
    Copy-Item -LiteralPath 'Docs/PORTABLE_RUNTIME_NOTICES.md' -Destination $qDestination
    $qLicenses = Join-Path $qDestination 'licenses'
    New-Item -ItemType Directory -Path $qLicenses -Force | Out-Null
    $qRuntimeRoot = Split-Path (Split-Path $qRuntime[0] -Parent) -Parent
    Get-ChildItem -LiteralPath $qRuntimeRoot -Recurse -File | Where-Object {
        $_.Name -match '^(LICENSE|NOTICE|COPYING|copyright)' -or $_.Name -match 'license.*\.txt$'
    } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $qLicenses ($_.FullName.Substring($qRuntimeRoot.Length + 1) -replace '[\\/]', '_')) }
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/swiftlang/swift/swift-6.1.2-RELEASE/LICENSE.txt' -OutFile (Join-Path $qLicenses 'Swift-LICENSE.txt')

    # Smoke-test with the developer runtime removed from the search path.
    $qOldPath = $env:Path
    try {
        $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
        & (Join-Path $qDestination 'q.exe') --help
        if ($LASTEXITCODE -ne 0) { throw 'Packaged CLI cannot run without the toolchain on PATH' }
        & (Join-Path $qDestination 'q.exe') list
        if ($LASTEXITCODE -ne 0) { throw 'Packaged CLI cannot enumerate serial candidates' }
    } finally { $env:Path = $qOldPath }
    git rev-parse HEAD | Set-Content -LiteralPath (Join-Path $qDestination 'COMMIT.txt')
    Compress-Archive -Path "$qDestination\*" -DestinationPath '.build/packages/q-windows-x64.zip' -Force
    Get-FileHash '.build/packages/q-windows-x64.zip' -Algorithm SHA256
} finally { Pop-Location }
