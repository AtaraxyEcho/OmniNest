# download_fonts.ps1 - Download Noto Sans SC font from Google Fonts
# Uses an older user agent (no woff2 support) so Google Fonts returns
# a single TTF file per weight instead of unicode-range subsets.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/download_fonts.ps1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$fontDir = Join-Path $PSScriptRoot '..\assets\fonts'
if (!(Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
}

$weights = @(400, 500, 600, 700)
# Old Firefox user agent — Google Fonts serves a single TTF per weight
$userAgent = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.1) Gecko/2008070208 Firefox/3.0.1'

Write-Host 'Fetching Google Fonts CSS (TTF mode)...' -ForegroundColor Cyan

foreach ($weight in $weights) {
    Write-Host "Downloading weight $weight ..." -ForegroundColor Cyan

    $cssUrl = "https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@${weight}&display=swap"
    $css = Invoke-WebRequest -Uri $cssUrl -UserAgent $userAgent -UseBasicParsing | Select-Object -ExpandProperty Content

    # Extract the single TTF URL from the @font-face block
    $pattern = 'url\((https://[^)]+\.ttf)\)'
    $match = [regex]::Match($css, $pattern)

    if (!$match.Success) {
        Write-Host "  WARN: TTF URL not found for weight $weight, skipping" -ForegroundColor Yellow
        continue
    }

    $ttfUrl = $match.Groups[1].Value
    $outFile = Join-Path $fontDir "NotoSansSC-$weight.ttf"

    Write-Host "  URL: $ttfUrl" -ForegroundColor Gray
    Invoke-WebRequest -Uri $ttfUrl -OutFile $outFile -UserAgent $userAgent -UseBasicParsing

    $size = [math]::Round((Get-Item $outFile).Length / 1MB, 2)
    Write-Host "  Saved: $outFile ($size MB)" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Font download complete!' -ForegroundColor Green
Write-Host 'Run: flutter clean && flutter pub get, then rebuild.' -ForegroundColor Yellow
