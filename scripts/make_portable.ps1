Param(
    [string]$ProjectRoot = "$(Resolve-Path ..\)"
)

# Usage: .\make_portable.ps1 (run from project root) or provide -ProjectRoot
# Copies Windows release build to TimeTrak_Portable\windows and zips it.

$cwd = (Get-Location).Path
$releaseDir = Join-Path $cwd "build\windows\x64\runner\Release"
$portableDir = Join-Path $cwd "TimeTrak_Portable\windows"
$zipPath = Join-Path $cwd "TimeTrak_Portable\TimeTrak_Portable_Windows.zip"

if (-not (Test-Path $releaseDir)) {
    Write-Error "Release directory not found: $releaseDir`nRun `flutter build windows --release` first."
    exit 1
}

# Create portable windows dir
if (-not (Test-Path $portableDir)) {
    New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
}

# Copy release contents
Write-Output "Copying release artifacts from `$releaseDir` to `$portableDir`..."
Copy-Item -Path (Join-Path $releaseDir '*') -Destination $portableDir -Recurse -Force

# Create zip
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Write-Output "Creating ZIP: $zipPath"
Compress-Archive -Path (Join-Path $portableDir '*') -DestinationPath $zipPath -Force

Write-Output "Portable build created: $zipPath"
Write-Output "Contents of TimeTrak_Portable/windows:"
Get-ChildItem -Path $portableDir -Recurse | Select-Object FullName, Length | Format-Table -AutoSize
