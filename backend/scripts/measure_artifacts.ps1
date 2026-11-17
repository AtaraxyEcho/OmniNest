param(
    [switch]$SkipBuild,
    [string]$OutputDirectory = 'target/reports/artifacts',
    [ValidateRange(1, [long]::MaxValue)]
    [long]$BaselineSizeBytes = 174086947,
    [ValidateRange(0, 100)]
    [double]$MaxGrowthPercent = 3
)

$ErrorActionPreference = 'Stop'

function Get-CommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $Command 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw "Command failed with exit code $exitCode"
    }

    return ($output -join "`n").Trim()
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

if (-not $SkipBuild) {
    & mvn -pl omninest-app -am package -DskipTests
    if ($LASTEXITCODE -ne 0) {
        throw "Maven release build failed with exit code $LASTEXITCODE"
    }
}

$jar = Get-ChildItem -LiteralPath 'omninest-app/target' -Filter '*.jar' -File |
    Where-Object { $_.Name -notlike '*.original' } |
    Sort-Object Length -Descending |
    Select-Object -First 1

if ($null -eq $jar) {
    throw 'No omninest-app Boot JAR found. Build it first or remove -SkipBuild.'
}

$maximumAllowedSizeBytes = [long][math]::Floor(
    $BaselineSizeBytes * (1 + $MaxGrowthPercent / 100)
)
$growthPercent = (($jar.Length - $BaselineSizeBytes) / $BaselineSizeBytes) * 100
$withinGrowthBudget = $jar.Length -le $maximumAllowedSizeBytes

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($jar.FullName)
try {
    $dependencies = @(
        $archive.Entries |
            Where-Object { $_.FullName.StartsWith('BOOT-INF/lib/') -and $_.Name.EndsWith('.jar') } |
            ForEach-Object {
                [pscustomobject]@{
                    name = $_.Name
                    sizeBytes = $_.Length
                    compressedSizeBytes = $_.CompressedLength
                }
            } |
            Sort-Object sizeBytes -Descending
    )
}
finally {
    $archive.Dispose()
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportDirectory = Join-Path (Get-Location) $OutputDirectory
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null

$report = [ordered]@{
    measuredAt = (Get-Date).ToUniversalTime().ToString('o')
    gitSha = Get-CommandOutput { git rev-parse HEAD }
    javaVersion = Get-CommandOutput { java -version }
    mavenVersion = Get-CommandOutput { mvn -version }
    artifact = [ordered]@{
        path = Get-RelativePath $jar.FullName
        sizeBytes = $jar.Length
        baselineSizeBytes = $BaselineSizeBytes
        maximumAllowedSizeBytes = $maximumAllowedSizeBytes
        growthPercent = [math]::Round($growthPercent, 4)
        maxGrowthPercent = $MaxGrowthPercent
        withinGrowthBudget = $withinGrowthBudget
        dependencyCount = $dependencies.Count
        dependencySizeBytes = ($dependencies | Measure-Object -Property sizeBytes -Sum).Sum
        compressedDependencySizeBytes = ($dependencies | Measure-Object -Property compressedSizeBytes -Sum).Sum
    }
    largestDependencies = @($dependencies | Select-Object -First 50)
}

$jsonPath = Join-Path $reportDirectory "backend-artifacts-$timestamp.json"
$csvPath = Join-Path $reportDirectory "backend-dependencies-$timestamp.csv"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$dependencies | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Backend artifact report: $(Get-RelativePath $jsonPath)"
Write-Host "Dependency size report: $(Get-RelativePath $csvPath)"
Write-Host "Boot JAR: $([math]::Round($jar.Length / 1MB, 2)) MiB"
Write-Host "Baseline growth: $([math]::Round($growthPercent, 2))% / $MaxGrowthPercent%"

if (-not $withinGrowthBudget) {
    throw "Boot JAR exceeds the accepted growth budget: $($jar.Length) bytes > $maximumAllowedSizeBytes bytes"
}
