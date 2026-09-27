# 重新应用 Flutter 插件对 AGP 9 Built-in Kotlin 的兼容补丁。
# 目标插件的 android/build.gradle 会无条件 apply kotlin-android，
# 且部分使用 android.kotlinOptions；二者都与 android.builtInKotlin=true 冲突。
# Flutter 的 KGP 检测是静态正则扫描脚本文本，因此 apply 必须写成
# pluginManager.apply('kotlin-android')，避免条件分支仍被误报。
# 该脚本在 pub cache 清理或重装后需要重新执行。
$ErrorActionPreference = 'Stop'
$pubCache = Join-Path $env:LOCALAPPDATA 'Pub\Cache\hosted\pub.dev'

function Get-PackageBuildGradle {
    param([string]$Filter)
    $target = Get-ChildItem $pubCache -Directory -Filter $Filter |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $target) {
        throw "package matching '$Filter' not found under $pubCache"
    }
    $buildGradle = Join-Path $target.FullName 'android\build.gradle'
    if (-not (Test-Path $buildGradle)) {
        throw "missing $buildGradle"
    }
    return $buildGradle
}

function Convert-ApplyPluginSyntax {
    param([string]$Content)
    $old = "apply plugin: 'kotlin-android'"
    $new = "project.pluginManager.apply('kotlin-android')"
    return $Content.Replace($old, $new)
}

function Save-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Patch-FlutterTts {
    $buildGradle = Get-PackageBuildGradle 'flutter_tts-4.*'
    $content = [System.IO.File]::ReadAllText($buildGradle)
    $changed = $false

    if ($content -notmatch 'builtInKotlin') {
        $oldApply = "apply plugin: 'kotlin-android'"
        if ($content -notmatch [regex]::Escape($oldApply)) {
            throw "expected kotlin-android apply not found in $buildGradle"
        }
        $newApply = @'
// Apply KGP only when AGP does not provide built-in Kotlin (AGP 9+).
def builtInKotlin = false
if (project.hasProperty('android.builtInKotlin')) {
    builtInKotlin = project.property('android.builtInKotlin').toString().toBoolean()
} else {
    def agpMajorTts = 0
    try {
        agpMajorTts = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.tokenize('.')[0].toInteger()
    } catch (ignored) {
        agpMajorTts = 0
    }
    builtInKotlin = agpMajorTts >= 9
}
if (!builtInKotlin) {
    project.pluginManager.apply('kotlin-android')
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}
'@
        $content = $content.Replace($oldApply, $newApply)
        $oldOptions = @'
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11
    }
'@
        if ($content.Contains($oldOptions)) {
            $content = $content.Replace($oldOptions, '')
        }
        $changed = $true
    }

    $updated = Convert-ApplyPluginSyntax -Content $content
    if ($updated -ne $content) {
        $content = $updated
        $changed = $true
    }

    if ($changed) {
        Save-Utf8NoBom -Path $buildGradle -Content $content
        Write-Host "patched: $buildGradle"
    } else {
        Write-Host "already patched: $buildGradle"
    }
}

function Patch-DesktopDrop {
    $buildGradle = Get-PackageBuildGradle 'desktop_drop-0.8.*'
    $content = [System.IO.File]::ReadAllText($buildGradle)
    $updated = Convert-ApplyPluginSyntax -Content $content
    if ($updated -ne $content) {
        Save-Utf8NoBom -Path $buildGradle -Content $updated
        Write-Host "patched: $buildGradle"
    } else {
        Write-Host "already patched: $buildGradle"
    }
}

Patch-FlutterTts
Patch-DesktopDrop
