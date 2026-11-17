param(
    [string]$Executable = 'build/windows/x64/runner/Release/omninest_frontend.exe',
    [ValidateRange(0, 300)]
    [int]$WarmupSeconds = 15,
    [ValidateRange(5, 3600)]
    [int]$SampleSeconds = 60,
    [ValidateRange(1, 60)]
    [int]$IntervalSeconds = 2,
    [string]$OutputDirectory = 'build/reports/runtime',
    [switch]$ShowWindow,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

function Get-Percentile {
    param(
        [Parameter(Mandatory = $true)]
        [long[]]$Values,
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 1)]
        [double]$Percentile
    )

    if ($Values.Count -eq 0) {
        return 0
    }

    $sorted = @($Values | Sort-Object)
    $index = [math]::Ceiling(($sorted.Count - 1) * $Percentile)
    return $sorted[$index]
}

function Get-GitSha {
    $output = (& git rev-parse HEAD 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Git revision: $($output -join "`n")"
    }
    return ($output -join "`n").Trim()
}

$resolvedExecutable = Resolve-Path -LiteralPath $Executable -ErrorAction Stop
$executableFile = Get-Item -LiteralPath $resolvedExecutable.Path
$workingDirectory = $executableFile.DirectoryName
$releaseDirectorySize = (
    Get-ChildItem -LiteralPath $workingDirectory -Recurse -File |
        Measure-Object -Property Length -Sum
).Sum
$process = $null
$samples = [System.Collections.Generic.List[object]]::new()

try {
    $startParameters = @{
        FilePath = $resolvedExecutable.Path
        WorkingDirectory = $workingDirectory
        PassThru = $true
    }
    if (-not $ShowWindow) {
        $startParameters.WindowStyle = 'Hidden'
    }

    $startedAt = (Get-Date).ToUniversalTime()
    $process = Start-Process @startParameters
    Start-Sleep -Seconds $WarmupSeconds

    $deadline = (Get-Date).ToUniversalTime().AddSeconds($SampleSeconds)
    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        if ($process.HasExited) {
            throw "Windows Release process exited before sampling completed, exit code $($process.ExitCode)."
        }

        $process.Refresh()
        $samples.Add([pscustomobject]@{
            sampledAt = (Get-Date).ToUniversalTime().ToString('o')
            elapsedSeconds = [math]::Round(((Get-Date).ToUniversalTime() - $startedAt).TotalSeconds, 3)
            workingSetBytes = $process.WorkingSet64
            privateMemoryBytes = $process.PrivateMemorySize64
            pagedMemoryBytes = $process.PagedMemorySize64
            threadCount = $process.Threads.Count
            handleCount = $process.HandleCount
            cpuSeconds = [math]::Round($process.TotalProcessorTime.TotalSeconds, 3)
        })
        Start-Sleep -Seconds $IntervalSeconds
    }

    if ($samples.Count -eq 0) {
        throw 'Windows Release runtime sampling produced no data.'
    }

    $workingSets = @($samples | ForEach-Object { [long]$_.workingSetBytes })
    $privateMemory = @($samples | ForEach-Object { [long]$_.privateMemoryBytes })
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportDirectory = Join-Path (Get-Location) $OutputDirectory
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null

    $report = [ordered]@{
        measuredAt = (Get-Date).ToUniversalTime().ToString('o')
        gitSha = Get-GitSha
        executable = [ordered]@{
            path = $Executable.Replace('\', '/')
            sizeBytes = $executableFile.Length
            releaseDirectorySizeBytes = $releaseDirectorySize
            sha256 = (Get-FileHash -LiteralPath $resolvedExecutable.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        scenario = [ordered]@{
            name = 'windows-release-idle'
            warmupSeconds = $WarmupSeconds
            sampleSeconds = $SampleSeconds
            intervalSeconds = $IntervalSeconds
            windowVisible = [bool]$ShowWindow
        }
        process = [ordered]@{
            id = $process.Id
            sampleCount = $samples.Count
            workingSetBytes = [ordered]@{
                minimum = ($workingSets | Measure-Object -Minimum).Minimum
                median = Get-Percentile -Values $workingSets -Percentile 0.5
                p95 = Get-Percentile -Values $workingSets -Percentile 0.95
                maximum = ($workingSets | Measure-Object -Maximum).Maximum
            }
            privateMemoryBytes = [ordered]@{
                minimum = ($privateMemory | Measure-Object -Minimum).Minimum
                median = Get-Percentile -Values $privateMemory -Percentile 0.5
                p95 = Get-Percentile -Values $privateMemory -Percentile 0.95
                maximum = ($privateMemory | Measure-Object -Maximum).Maximum
            }
            maximumThreadCount = ($samples | Measure-Object -Property threadCount -Maximum).Maximum
            maximumHandleCount = ($samples | Measure-Object -Property handleCount -Maximum).Maximum
            finalCpuSeconds = $samples[$samples.Count - 1].cpuSeconds
        }
    }

    $jsonPath = Join-Path $reportDirectory "windows-runtime-$timestamp.json"
    $csvPath = Join-Path $reportDirectory "windows-runtime-$timestamp.csv"
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $samples | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    Write-Host "Windows runtime report: $($jsonPath.Substring((Get-Location).Path.Length + 1).Replace('\', '/'))"
    Write-Host "Windows runtime samples: $($csvPath.Substring((Get-Location).Path.Length + 1).Replace('\', '/'))"
    Write-Host "Working set p95: $([math]::Round($report.process.workingSetBytes.p95 / 1MB, 2)) MiB"
    Write-Host "Private memory p95: $([math]::Round($report.process.privateMemoryBytes.p95 / 1MB, 2)) MiB"
}
finally {
    if ($null -ne $process -and -not $KeepRunning -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000) | Out-Null
    }
}
