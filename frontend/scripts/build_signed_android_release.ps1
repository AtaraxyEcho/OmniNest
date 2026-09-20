[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$|^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedCertificateSha256,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [ValidatePattern('^https?://')]
    [string]$ApiBaseUrl = '',

    [switch]$RequireHttps,

    [string]$FlutterCommand = '',
    [string]$JarsignerPath = '',
    [string]$KeytoolPath = ''
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

function Resolve-JavaTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [string]$ExplicitPath = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return $ExplicitPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $javaHomeCandidate = Join-Path $env:JAVA_HOME "bin\${ToolName}.exe"
        if (Test-Path -LiteralPath $javaHomeCandidate -PathType Leaf) {
            return $javaHomeCandidate
        }
    }
    $command = Get-Command "${ToolName}.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    throw "${ToolName}.exe was not found. Set JAVA_HOME or pass an explicit tool path."
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

$requiredEnvironment = @(
    'OMNINEST_ANDROID_KEYSTORE_PATH',
    'OMNINEST_ANDROID_KEYSTORE_PASSWORD',
    'OMNINEST_ANDROID_KEY_ALIAS',
    'OMNINEST_ANDROID_KEY_PASSWORD'
)
$missingEnvironment = @(
    $requiredEnvironment | Where-Object {
        [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
    }
)
if ($missingEnvironment.Count -gt 0) {
    throw "Missing required signing environment variables: $($missingEnvironment -join ', ')"
}
if ($env:OMNINEST_ALLOW_DEBUG_RELEASE_SIGNING -eq 'true') {
    throw 'Debug release signing override must be disabled for formal Android releases.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
if ($RequireHttps -and $ApiBaseUrl -match '^http://') {
    throw '-RequireHttps 与 http:// 开头的 -ApiBaseUrl 互斥：预置地址必须使用 HTTPS。'
}
$flutter = Resolve-FlutterCommand
$jarsigner = Resolve-JavaTool -ToolName 'jarsigner' -ExplicitPath $JarsignerPath
$keytool = Resolve-JavaTool -ToolName 'keytool' -ExplicitPath $KeytoolPath
$bundle = Join-Path $projectRoot 'build\app\outputs\bundle\release\app-release.aab'
$manifestDirectory = Join-Path $projectRoot 'build\release-manifests'
$manifestPath = Join-Path $manifestDirectory 'android-release.json'
$expectedFingerprint = $ExpectedCertificateSha256.Replace(':', '').ToUpperInvariant()

Push-Location $projectRoot
try {
    # ApiBaseUrl 可选：不传构建通用包（首启引导配置服务器），传入则作为预置地址。
    $dartDefines = @()
    if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
        $dartDefines += "--dart-define=OMNINEST_API_BASE_URL=$ApiBaseUrl"
    }
    if ($RequireHttps) {
        $dartDefines += '--dart-define=OMNINEST_REQUIRE_HTTPS=true'
    }
    Invoke-CheckedCommand -Command $flutter -Arguments @(
        'build', 'appbundle', '--release', '--no-pub'
    ) + $dartDefines
    if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
        throw "Android App Bundle was not found: $bundle"
    }

    Invoke-CheckedCommand -Command $jarsigner -Arguments @('-verify', $bundle)
    $certificateOutput = & $keytool `
        '-J-Duser.language=en' `
        '-J-Duser.country=US' `
        '-printcert' `
        '-jarfile' $bundle 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed to read the bundle certificate with exit code $LASTEXITCODE."
    }
    $certificateText = $certificateOutput -join "`n"
    $fingerprintMatch = [regex]::Match($certificateText, 'SHA256:\s*([0-9A-F:]{95})')
    if (-not $fingerprintMatch.Success) {
        throw 'Unable to read the SHA-256 signer certificate fingerprint from the bundle.'
    }
    $actualFingerprint = $fingerprintMatch.Groups[1].Value.Replace(':', '').ToUpperInvariant()
    if ($actualFingerprint -ne $expectedFingerprint) {
        throw "Android signer certificate fingerprint mismatch. Actual: $actualFingerprint"
    }

    $versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') `
        -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
    $version = if ($null -eq $versionLine) { 'unknown' } else { $versionLine.Matches[0].Groups[1].Value }
    $hash = Get-FileHash -LiteralPath $bundle -Algorithm SHA256
    New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
    [ordered]@{
        product = 'OmniNest'
        applicationId = 'com.omninest.app'
        version = $version
        artifact = 'build/app/outputs/bundle/release/app-release.aab'
        sizeBytes = (Get-Item -LiteralPath $bundle).Length
        sha256 = $hash.Hash.ToLowerInvariant()
        certificateSha256 = $actualFingerprint.ToLowerInvariant()
        keyAlias = $env:OMNINEST_ANDROID_KEY_ALIAS
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8

    Write-Host "Signed Android App Bundle: $bundle"
    Write-Host "Release manifest: $manifestPath"
}
finally {
    Pop-Location
}
