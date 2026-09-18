[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https?://')]
    [string]$TimestampUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https?://')]
    [string]$ApiBaseUrl,

    [string]$FlutterCommand = '',
    [string]$SignToolPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FlutterCommand {
    if (-not [string]::IsNullOrWhiteSpace($FlutterCommand)) {
        return $FlutterCommand
    }
    if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_ROOT)) {
        return Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
    }
    $command = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'Flutter was not found. Set FLUTTER_ROOT or pass -FlutterCommand.'
    }
    return $command.Source
}

function Resolve-SignTool {
    if (-not [string]::IsNullOrWhiteSpace($SignToolPath)) {
        return $SignToolPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:OMNINEST_SIGNTOOL_PATH)) {
        return $env:OMNINEST_SIGNTOOL_PATH
    }
    $command = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $windowsKitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $windowsKitsRoot) {
        $candidate = Get-ChildItem -Path $windowsKitsRoot -Filter 'signtool.exe' -Recurse |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate.FullName
        }
    }
    throw 'signtool.exe was not found. Install Windows SDK or pass -SignToolPath.'
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$normalizedThumbprint = $CertificateThumbprint.ToUpperInvariant()
$certificatePath = "Cert:\CurrentUser\My\$normalizedThumbprint"
$certificate = Get-Item -LiteralPath $certificatePath -ErrorAction SilentlyContinue
if ($null -eq $certificate) {
    throw "Certificate was not found in CurrentUser/My: $normalizedThumbprint"
}
if (-not $certificate.HasPrivateKey) {
    throw "Code-signing certificate has no private key: $normalizedThumbprint"
}
if ($certificate.NotAfter -le (Get-Date)) {
    throw "Code-signing certificate has expired: $normalizedThumbprint"
}

$flutter = Resolve-FlutterCommand
$signTool = Resolve-SignTool
$executable = Join-Path $projectRoot 'build\windows\x64\runner\Release\omninest_frontend.exe'
$manifestDirectory = Join-Path $projectRoot 'build\release-manifests'
$manifestPath = Join-Path $manifestDirectory 'windows-release.json'

Push-Location $projectRoot
try {
    # release 构建必须显式指定 API 基地址（environment.fromDefines 会 fail-fast）。
    Invoke-CheckedCommand -Command $flutter -Arguments @(
        'build', 'windows', '--release', '--no-pub',
        "--dart-define=OMNINEST_API_BASE_URL=$ApiBaseUrl"
    )
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Windows Release executable was not found: $executable"
    }

    Invoke-CheckedCommand -Command $signTool -Arguments @(
        'sign',
        '/sha1', $normalizedThumbprint,
        '/s', 'My',
        '/fd', 'SHA256',
        '/tr', $TimestampUrl,
        '/td', 'SHA256',
        '/v',
        $executable
    )
    Invoke-CheckedCommand -Command $signTool -Arguments @('verify', '/pa', '/all', '/v', $executable)

    $signature = Get-AuthenticodeSignature -LiteralPath $executable
    if ($signature.Status -ne 'Valid') {
        throw "Authenticode validation failed: $($signature.StatusMessage)"
    }
    if ($signature.SignerCertificate.Thumbprint -ne $normalizedThumbprint) {
        throw 'Signer certificate thumbprint does not match the release parameter.'
    }

    $versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') `
        -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
    $version = if ($null -eq $versionLine) { 'unknown' } else { $versionLine.Matches[0].Groups[1].Value }
    $hash = Get-FileHash -LiteralPath $executable -Algorithm SHA256
    New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
    [ordered]@{
        product = 'OmniNest'
        version = $version
        artifact = 'build/windows/x64/runner/Release/omninest_frontend.exe'
        sizeBytes = (Get-Item -LiteralPath $executable).Length
        sha256 = $hash.Hash.ToLowerInvariant()
        certificateThumbprint = $normalizedThumbprint
        certificateSubject = $signature.SignerCertificate.Subject
        timestampUrl = $TimestampUrl
        signedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8

    Write-Host "Signed Windows release: $executable"
    Write-Host "Release manifest: $manifestPath"
}
finally {
    Pop-Location
}
