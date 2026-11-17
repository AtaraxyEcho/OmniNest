param(
    [ValidateSet('android-aab', 'android-apk-split', 'windows', 'web')]
    [string[]]$BuildTarget = @(),
    [string]$OutputDirectory = 'build/reports/artifacts'
)

$ErrorActionPreference = 'Stop'

function Invoke-FlutterBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    switch ($Target) {
        'android-aab' {
            & flutter build appbundle --release
            break
        }
        'android-apk-split' {
            & flutter build apk --release --split-per-abi
            break
        }
        'windows' {
            & flutter build windows --release
            break
        }
        'web' {
            & flutter build web --release
            break
        }
        default {
            throw "Unsupported build target: $Target"
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Flutter release build failed for $Target with exit code $LASTEXITCODE"
    }
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected release artifact is missing: $Path"
    }
}

function Assert-BuildOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    switch ($Target) {
        'android-aab' {
            Assert-FileExists -Path 'build/app/outputs/bundle/release/app-release.aab'
            break
        }
        'android-apk-split' {
            foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
                $path = "build/app/outputs/flutter-apk/app-$abi-release.apk"
                Assert-FileExists -Path $path
            }
            break
        }
        'windows' {
            Assert-FileExists -Path 'build/windows/x64/runner/Release/omninest_frontend.exe'
            Assert-FileExists -Path 'build/windows/x64/runner/Release/data/flutter_assets/AssetManifest.bin'
            break
        }
        'web' {
            foreach ($path in @(
                'build/web/main.dart.js',
                'build/web/flutter_bootstrap.js',
                'build/web/assets/AssetManifest.bin'
            )) {
                Assert-FileExists -Path $path
            }
            $unresolvedTokens = Select-String -Path 'build/web/index.html', 'build/web/flutter_bootstrap.js' -Pattern '\{\{[^}]+\}\}'
            if ($unresolvedTokens) {
                throw 'Web release output contains unresolved Flutter template tokens.'
            }
            break
        }
        default {
            throw "Unsupported build target: $Target"
        }
    }
}

function Get-DirectorySize {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $null
    }

    return (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop |
        Measure-Object -Property Length -Sum).Sum
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $basePath = (Get-Location).Path.TrimEnd('\') + '\'
    $baseUri = [System.Uri]::new($basePath)
    $pathUri = [System.Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

function Add-FileArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Artifacts,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    Get-ChildItem -Path $Pattern -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.gitkeep' } |
        ForEach-Object {
            $Artifacts.Add([pscustomobject]@{
                type = $Type
                path = Get-RelativePath $_.FullName
                sizeBytes = $_.Length
            })
        }
}

foreach ($target in $BuildTarget) {
    Invoke-FlutterBuild -Target $target
    Assert-BuildOutput -Target $target
}

$artifacts = [System.Collections.Generic.List[object]]::new()
Add-FileArtifacts -Artifacts $artifacts -Pattern 'build/app/outputs/bundle/release/*.aab' -Type 'android-aab'
Add-FileArtifacts -Artifacts $artifacts -Pattern 'build/app/outputs/flutter-apk/*release*.apk' -Type 'android-apk'
Add-FileArtifacts -Artifacts $artifacts -Pattern 'assets/fonts/*' -Type 'font'

$directoryArtifacts = @(
    @{ type = 'windows-release'; path = 'build/windows/x64/runner/Release' },
    @{ type = 'web-release'; path = 'build/web' }
)
foreach ($item in $directoryArtifacts) {
    $size = Get-DirectorySize -Path $item.path
    if ($null -ne $size) {
        $resolvedPath = (Resolve-Path -LiteralPath $item.path).Path
        $artifacts.Add([pscustomobject]@{
            type = $item.type
            path = Get-RelativePath $resolvedPath
            sizeBytes = $size
        })
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportDirectory = Join-Path (Get-Location) $OutputDirectory
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$flutterVersion = ((& flutter --version --machine 2>&1) -join "`n").Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read Flutter version, exit code $LASTEXITCODE"
}

$report = [ordered]@{
    measuredAt = (Get-Date).ToUniversalTime().ToString('o')
    gitSha = ((& git rev-parse HEAD 2>&1) -join "`n").Trim()
    flutterVersion = $flutterVersion | ConvertFrom-Json
    builtTargets = @($BuildTarget)
    artifactCount = $artifacts.Count
    totalSizeBytes = ($artifacts | Measure-Object -Property sizeBytes -Sum).Sum
    artifacts = @($artifacts | Sort-Object sizeBytes -Descending)
}

$jsonPath = Join-Path $reportDirectory "frontend-artifacts-$timestamp.json"
$csvPath = Join-Path $reportDirectory "frontend-artifacts-$timestamp.csv"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$artifacts | Sort-Object sizeBytes -Descending |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Frontend artifact report: $(Get-RelativePath $jsonPath)"
Write-Host "Artifact size report: $(Get-RelativePath $csvPath)"
Write-Host "Artifacts found: $($artifacts.Count)"
