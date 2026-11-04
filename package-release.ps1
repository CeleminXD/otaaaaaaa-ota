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
$descriptionFile = Join-Path $projectPath 'build/project_description.json'
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
if (-not (Test-Path -LiteralPath $descriptionFile -PathType Leaf)) {
    throw "No existe $descriptionFile. Ejecuta idf.py build antes de empaquetar."
}

$description = Get-Content -LiteralPath $descriptionFile -Raw | ConvertFrom-Json
if ([string]$description.project_version -cne $Version) {
    throw "El firmware compilado declara la versión '$($description.project_version)', no '$Version'."
}
$target = [string]$description.target
if ($target -notmatch '^esp32[a-z0-9]+$') {
    throw "El destino ESP-IDF no es válido: '$target'."
}
$model = [string]$description.project_name
if ($model -notmatch '^[A-Za-z0-9_.-]{1,31}$') {
    throw "El nombre de modelo/proyecto no es válido: '$model'."
}

$sourceVersionTime = (Get-Item -LiteralPath $versionFile).LastWriteTimeUtc
$firmwareTime = (Get-Item -LiteralPath $firmwareFile).LastWriteTimeUtc
if ($firmwareTime -lt $sourceVersionTime) {
    throw 'El binario es anterior a version.txt. Ejecuta idf.py build y vuelve a empaquetar.'
}

$manifest = [ordered]@{
    version = $Version
    url = $firmwareUrl
    model = $model
    target = $target
    sha256 = (Get-FileHash -LiteralPath $firmwareFile -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifestJson = $manifest | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $distPath | Out-Null
$packagedFirmware = Join-Path $distPath $firmwareName
$checksumFile = "$packagedFirmware.sha256"
Copy-Item -LiteralPath $firmwareFile -Destination $packagedFirmware -Force
$packagedSha256 = (Get-FileHash -LiteralPath $packagedFirmware -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packagedSha256 -cne $manifest.sha256) {
    throw 'El SHA-256 del binario empaquetado no coincide con el firmware compilado.'
}
[System.IO.File]::WriteAllText($checksumFile, "$($manifest.sha256)`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $distPath 'manifest.json'), $manifestJson, $utf8NoBom)

Write-Host "Binario listo para adjuntar al Release: $packagedFirmware"
Write-Host "Checksum listo para adjuntar al Release: $checksumFile"
Write-Host "Destino: $target; SHA-256: $($manifest.sha256)"
Write-Host "Manifiesto de referencia local (no subir): $(Join-Path $distPath 'manifest.json')"
Write-Host "URL estable del manifiesto para menuconfig: $manifestUrl"
Write-Host "Publica el Release v$Version con el binario; GitHub Actions actualizara manifest.json en main."
