param(
    [string]$ArchiveUrl = "https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-2026-06-01-git-bf608f16fd-full_build.7z",
    [string]$InstallRoot = "",
    [switch]$Force,
    [switch]$UpdateEnvFile
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $PSScriptRoot
if (-not $InstallRoot) {
    $InstallRoot = Join-Path $Root ".local\ffmpeg"
}

$DownloadRoot = Join-Path $InstallRoot "downloads"
$ToolRoot = Join-Path $InstallRoot "tools"

function New-DirectoryIfMissing {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Save-File {
    param(
        [string]$Url,
        [string]$Path
    )

    if ((Test-Path $Path) -and -not $Force) {
        return
    }

    New-DirectoryIfMissing -Path (Split-Path -Parent $Path)
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
}

function Find-ProjectExecutable {
    param([string]$Name)

    if (-not (Test-Path $InstallRoot)) {
        return $null
    }

    $found = Get-ChildItem -Path $InstallRoot -Filter "$Name.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*\bin\$Name.exe" } |
        Sort-Object FullName |
        Select-Object -First 1

    if ($found) {
        return $found.FullName
    }

    return $null
}

function Resolve-ArchiveTool {
    foreach ($name in @("7z.exe", "7za.exe", "7zr.exe")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    foreach ($candidate in @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $portable7z = Join-Path $ToolRoot "7zr.exe"
    Save-File -Url "https://www.7-zip.org/a/7zr.exe" -Path $portable7z
    return $portable7z
}

function Format-DotEnvValue {
    param([string]$Value)

    return "'" + $Value.Replace("'", "\'") + "'"
}

function Set-DotEnvValues {
    param(
        [string]$Path,
        [hashtable]$Values
    )

    $lines = New-Object "System.Collections.Generic.List[string]"
    if (Test-Path $Path) {
        foreach ($line in Get-Content $Path) {
            [void]$lines.Add($line)
        }
    }

    foreach ($key in $Values.Keys) {
        $formattedValue = Format-DotEnvValue -Value ([string]$Values[$key])
        $nextLine = "$key=$formattedValue"
        $matched = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match "^\s*$([Regex]::Escape($key))\s*=") {
                $lines[$index] = $nextLine
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            [void]$lines.Add($nextLine)
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

New-DirectoryIfMissing -Path $InstallRoot
New-DirectoryIfMissing -Path $DownloadRoot

if ($Force) {
    Get-ChildItem -Path $InstallRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("downloads", "tools") } |
        Remove-Item -Recurse -Force
}

$ffmpegPath = Find-ProjectExecutable -Name "ffmpeg"
$ffprobePath = Find-ProjectExecutable -Name "ffprobe"

if (-not $ffmpegPath -or -not $ffprobePath) {
    $archiveUri = [Uri]$ArchiveUrl
    $archiveName = [System.IO.Path]::GetFileName($archiveUri.AbsolutePath)
    $archivePath = Join-Path $DownloadRoot $archiveName
    Save-File -Url $ArchiveUrl -Path $archivePath

    $archiveTool = Resolve-ArchiveTool
    & $archiveTool x $archivePath "-o$InstallRoot" -y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg archive extraction failed with exit code $LASTEXITCODE."
    }

    $ffmpegPath = Find-ProjectExecutable -Name "ffmpeg"
    $ffprobePath = Find-ProjectExecutable -Name "ffprobe"
}

if (-not $ffmpegPath -or -not $ffprobePath) {
    throw "ffmpeg.exe or ffprobe.exe was not found under $InstallRoot."
}

if ($UpdateEnvFile) {
    Set-DotEnvValues -Path (Join-Path $Root ".env") -Values @{
        FFMPEG_PATH = $ffmpegPath
        FFPROBE_PATH = $ffprobePath
    }
}

[pscustomobject]@{
    FFMPEG_PATH = $ffmpegPath
    FFPROBE_PATH = $ffprobePath
    INSTALL_DIR = (Resolve-Path $InstallRoot).Path
} | ConvertTo-Json -Compress
