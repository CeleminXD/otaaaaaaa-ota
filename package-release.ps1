param(
    [Parameter(Mandatory = $true)]
    [string]$EspProjectPath,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$GitHubRepository
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$') {
    throw 'Version debe tener formato MAJOR.MINOR.PATCH, por ejemplo 1.0.1.'
}
if ($GitHubRepository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw 'GitHubRepository debe tener formato OWNER/REPOSITORY.'
}

$projectPath = (Resolve-Path -LiteralPath $EspProjectPath).Path
$versionFile = Join-Path $projectPath 'version.txt'
$firmwareFile = Join-Path $projectPath 'build/otaaaaaaa.bin'
$repositoryRoot = $PSScriptRoot
$distPath = Join-Path $repositoryRoot 'dist'
$firmwareName = "otaaaaaaa-v$Version.bin"
$firmwareUrl = "https://github.com/$GitHubRepository/releases/download/v$Version/$firmwareName"
$manifestUrl = "https://raw.githubusercontent.com/$GitHubRepository/main/manifest.json"

if ($firmwareUrl.Length -ge 200) {
    throw "La URL del firmware tiene $($firmwareUrl.Length) caracteres; el componente OTA admite menos de 200."
}
if ($manifestUrl.Length -ge 200) {
    throw "La URL del manifiesto tiene $($manifestUrl.Length) caracteres; el componente OTA admite menos de 200."
}

if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "No existe version.txt en el proyecto ESP32: $versionFile"
}
if ((Get-Content -LiteralPath $versionFile -Raw).Trim() -cne $Version) {
    throw "version.txt no coincide con $Version. Actualiza la versión del proyecto ESP32 y compílalo."
}
if (-not (Test-Path -LiteralPath $firmwareFile -PathType Leaf)) {
    throw "No existe $firmwareFile. Compila el firmware con idf.py build."
}

$sourceVersionTime = (Get-Item -LiteralPath $versionFile).LastWriteTimeUtc
$firmwareTime = (Get-Item -LiteralPath $firmwareFile).LastWriteTimeUtc
if ($firmwareTime -lt $sourceVersionTime) {
    throw 'El binario es anterior a version.txt. Ejecuta idf.py build y vuelve a empaquetar.'
}

$manifest = [ordered]@{
    version = $Version
    url = $firmwareUrl
}
$manifestJson = $manifest | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $distPath | Out-Null
Copy-Item -LiteralPath $firmwareFile -Destination (Join-Path $distPath $firmwareName) -Force
[System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'manifest.json'), $manifestJson, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $distPath 'manifest.json'), $manifestJson, $utf8NoBom)

Write-Host "Binario listo para el Release: $(Join-Path $distPath $firmwareName)"
Write-Host "Manifiesto generado: $(Join-Path $repositoryRoot 'manifest.json')"
Write-Host "URL estable para menuconfig: $manifestUrl"
Write-Host "Siguiente: publica primero el binario en el Release v$Version y después sube manifest.json a main."
