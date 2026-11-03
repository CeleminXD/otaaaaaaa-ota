[CmdletBinding()]
param(
    [string]$EspProjectPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'otaaaaaaa'),
    [string]$GitHubRepository = 'CeleminXD/otaaaaaaa-ota',
    [ValidateRange(1, 30)]
    [int]$ActionTimeoutMinutes = 5
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-SemanticVersion([string]$Value) {
    if ($Value -notmatch '^v?(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$') {
        return $null
    }
    return [System.Version]::Parse("$($Matches[1]).$($Matches[2]).$($Matches[3])")
}

function Get-RemoteManifest([string]$GhPath, [string]$Repository) {
    $response = & $GhPath api "repos/$Repository/contents/manifest.json" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo leer manifest.json de GitHub: $($response -join ' ')"
    }
    $apiObject = ConvertFrom-Json -InputObject ($response -join [Environment]::NewLine)
    if ($apiObject.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace($apiObject.content)) {
        throw 'GitHub devolvió un manifiesto vacío o con formato inesperado.'
    }
    $jsonText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($apiObject.content))
    return ConvertFrom-Json -InputObject $jsonText
}

function Get-IdfPythonEnvironment([string[]]$ToolsRoots) {
    $required = 'tree-sitter-c freertos-gdb esptool esp-idf-nvs-partition-gen esp-idf-panic-decoder esp-idf-monitor esp-idf-size pyelftools idf-component-manager psutil tree-sitter esp-idf-kconfig pyclang esp-coredump click cryptography construct pyserial pyparsing'
    $pythonCode = "import importlib.metadata as m; [m.version(x) for x in '$required'.split()]"
    foreach ($root in ($ToolsRoots | Where-Object { $_ } | Select-Object -Unique)) {
        $pythonEnvRoot = Join-Path $root 'python_env'
        if (-not (Test-Path -LiteralPath $pythonEnvRoot -PathType Container)) { continue }
        foreach ($environment in (Get-ChildItem -LiteralPath $pythonEnvRoot -Directory -ErrorAction SilentlyContinue)) {
            $pythonExe = Join-Path $environment.FullName 'Scripts\python.exe'
            if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) { continue }
            & $pythonExe -c $pythonCode 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{ ToolsRoot = $root; Python = $pythonExe }
            }
        }
    }
    return $null
}

$projectPath = (Resolve-Path -LiteralPath $EspProjectPath).Path
$otaRepositoryPath = $PSScriptRoot
$versionFile = Join-Path $projectPath 'version.txt'
$packageScript = Join-Path $otaRepositoryPath 'package-release.ps1'
if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) { throw "No existe version.txt en $projectPath" }
if (-not (Test-Path -LiteralPath $packageScript -PathType Leaf)) { throw "No se encontró $packageScript" }

$ghCommand = Get-Command gh.exe -ErrorAction SilentlyContinue
if ($ghCommand) {
    $ghPath = $ghCommand.Source
} else {
    $portableGh = Join-Path $env:LOCALAPPDATA 'Programs\GitHubCLI\bin\gh.exe'
    if (Test-Path -LiteralPath $portableGh -PathType Leaf) {
        $ghPath = $portableGh
    } else {
        throw 'Falta GitHub CLI. Instálalo desde https://cli.github.com/ y vuelve a ejecutar.'
    }
}

$accountResult = & $ghPath api user --jq .login 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Autoriza GitHub CLI una vez con: & '$ghPath' auth login --hostname github.com --web --git-protocol https"
}
$account = ($accountResult -join '').Trim()
$owner = ($GitHubRepository -split '/', 2)[0]
if ($account -cne $owner) {
    throw "GitHub CLI usa la cuenta '$account'. Cambia a '$owner' con: & '$ghPath' auth switch --user $owner"
}

$releaseListResult = & $ghPath release list --repo $GitHubRepository --exclude-drafts --exclude-pre-releases --limit 100 --json tagName 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron consultar los Releases: $($releaseListResult -join ' ')"
}
$releaseList = ConvertFrom-Json -InputObject ($releaseListResult -join [Environment]::NewLine)
$latestReleaseVersion = $null
foreach ($release in @($releaseList)) {
    $candidate = Get-SemanticVersion ([string]$release.tagName)
    if ($candidate -and (-not $latestReleaseVersion -or $candidate -gt $latestReleaseVersion)) {
        $latestReleaseVersion = $candidate
    }
}
if (-not $latestReleaseVersion) { throw 'No se encontró un Release estable con etiqueta MAJOR.MINOR.PATCH.' }

$currentManifest = Get-RemoteManifest -GhPath $ghPath -Repository $GitHubRepository
$manifestVersion = Get-SemanticVersion ([string]$currentManifest.version)
if (-not $manifestVersion) { throw "La versión del manifiesto no es válida: $($currentManifest.version)" }
if ($manifestVersion -ne $latestReleaseVersion) {
    throw "GitHub está desincronizado: último Release $latestReleaseVersion, manifiesto $manifestVersion. Corrige primero la ejecución de Actions; no publicaré otra versión aún."
}

$currentVersionText = (Get-Content -LiteralPath $versionFile -Raw).Trim()
$currentProjectVersion = Get-SemanticVersion $currentVersionText
if (-not $currentProjectVersion) { throw "version.txt debe ser MAJOR.MINOR.PATCH; contiene '$currentVersionText'." }
if ($currentProjectVersion -gt $latestReleaseVersion) {
    $version = $currentProjectVersion.ToString(3)
} else {
    if ($latestReleaseVersion.Build -ge [int]::MaxValue) { throw 'El número de parche alcanzó el límite permitido.' }
    $version = ([System.Version]::new($latestReleaseVersion.Major, $latestReleaseVersion.Minor, $latestReleaseVersion.Build + 1)).ToString(3)
}
$tag = "v$version"
$assetName = "otaaaaaaa-v$version.bin"
$expectedAssetUrl = "https://github.com/$GitHubRepository/releases/download/$tag/$assetName"
if ($expectedAssetUrl.Length -ge 200) { throw 'La URL del firmware supera el límite del componente OTA.' }

$existingReleaseResult = & $ghPath release view $tag --repo $GitHubRepository --json isDraft,tagName 2>$null
$existingReleaseCode = $LASTEXITCODE
$resumeDraft = $false
if ($existingReleaseCode -eq 0) {
    $existingRelease = ConvertFrom-Json -InputObject ($existingReleaseResult -join [Environment]::NewLine)
    if (-not $existingRelease.isDraft) { throw "El Release $tag ya está publicado. Actualiza primero el manifiesto." }
    $resumeDraft = $true
}

$originalVersionContents = [System.IO.File]::ReadAllText($versionFile)
$versionFileChanged = $currentVersionText -cne $version
if ($versionFileChanged) {
    [System.IO.File]::WriteAllText($versionFile, "$version`r`n", $utf8NoBom)
    Write-Host "Versión del proyecto: $currentVersionText -> $version"
} else {
    Write-Host "Versión del proyecto: $version"
}

$releasePublished = $false
try {
    $idfPathCandidates = @($env:IDF_PATH, 'C:\esp\v5.4.4\esp-idf')
    $idfPath = $idfPathCandidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'export.ps1') -PathType Leaf) } | Select-Object -First 1
    if (-not $idfPath) { throw 'No encontré ESP-IDF. Configura IDF_PATH o instala ESP-IDF 5.4.4.' }

    $toolsCandidates = @($env:IDF_TOOLS_PATH, 'C:\idf-tools', 'C:\Espressif')
    $idfPython = Get-IdfPythonEnvironment -ToolsRoots $toolsCandidates
    if (-not $idfPython) { throw 'No encontré un entorno Python completo para ESP-IDF 5.4.' }
    $env:IDF_PATH = $idfPath
    $env:IDF_TOOLS_PATH = $idfPython.ToolsRoot

    Push-Location $projectPath
    try {
        . (Join-Path $idfPath 'export.ps1')
        if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) { throw 'ESP-IDF no expuso idf.py después de export.ps1.' }
        $activePython = Join-Path $env:IDF_PYTHON_ENV_PATH 'Scripts\python.exe'
        $cmakeCache = Join-Path $projectPath 'build\CMakeCache.txt'
        if (Test-Path -LiteralPath $cmakeCache -PathType Leaf) {
            $pythonCacheLine = Get-Content -LiteralPath $cmakeCache | Where-Object { $_ -match '^PYTHON:FILEPATH=' } | Select-Object -First 1
            if ($pythonCacheLine) {
                $configuredPython = $pythonCacheLine -replace '^PYTHON:FILEPATH=', ''
                if (-not [string]::Equals([System.IO.Path]::GetFullPath($configuredPython), [System.IO.Path]::GetFullPath($activePython), [System.StringComparison]::OrdinalIgnoreCase)) {
                    Write-Host 'El caché de compilación usa otro Python; limpiando solo los artefactos de build.'
                    idf.py fullclean
                    if ($LASTEXITCODE -ne 0) { throw "idf.py fullclean falló ($LASTEXITCODE)." }
                }
            }
        }
        idf.py reconfigure
        if ($LASTEXITCODE -ne 0) { throw "idf.py reconfigure falló ($LASTEXITCODE)." }
        idf.py build
        if ($LASTEXITCODE -ne 0) { throw "idf.py build falló ($LASTEXITCODE)." }
    } finally {
        Pop-Location
    }

    $descriptionPath = Join-Path $projectPath 'build\project_description.json'
    $description = Get-Content -LiteralPath $descriptionPath -Raw | ConvertFrom-Json
    if ([string]$description.project_version -cne $version) {
        throw "El firmware compilado dice versión $($description.project_version), no $version."
    }
    $binaryPath = Join-Path $projectPath 'build\otaaaaaaa.bin'
    if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf) -or (Get-Item -LiteralPath $binaryPath).Length -eq 0) {
        throw 'La compilación no generó build\otaaaaaaa.bin.'
    }

    & $packageScript -EspProjectPath $projectPath -Version $version -GitHubRepository $GitHubRepository
    if ($LASTEXITCODE -ne 0) { throw "El empaquetador falló ($LASTEXITCODE)." }
    $assetPath = Join-Path $otaRepositoryPath "dist\$assetName"
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf) -or (Get-Item -LiteralPath $assetPath).Length -eq 0) {
        throw "No se generó el asset $assetPath."
    }

    if (-not $resumeDraft) {
        & $ghPath release create $tag $assetPath --draft --repo $GitHubRepository --title "Firmware OTA $tag" --notes "Firmware ESP32-C6 $tag, compilado desde Visual Studio Code." --target main
        if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el borrador del Release $tag." }
    } else {
        Write-Host "Reanudando el borrador existente $tag y reemplazando su binario."
        & $ghPath release upload $tag $assetPath --clobber --repo $GitHubRepository
        if ($LASTEXITCODE -ne 0) { throw "No se pudo cargar el binario en el borrador $tag." }
    }

    $draftViewRaw = & $ghPath release view $tag --repo $GitHubRepository --json isDraft,assets 2>&1
    if ($LASTEXITCODE -ne 0) { throw "No se pudo verificar el borrador $tag." }
    $draftView = ConvertFrom-Json -InputObject ($draftViewRaw -join [Environment]::NewLine)
    $binaryAsset = @($draftView.assets) | Where-Object { $_.name -ceq $assetName } | Select-Object -First 1
    if (-not $draftView.isDraft -or -not $binaryAsset -or [long]$binaryAsset.size -ne (Get-Item -LiteralPath $assetPath).Length) {
        throw "El borrador $tag no contiene el binario completo con el nombre esperado. No se publicará."
    }

    $releaseStarted = [DateTimeOffset]::UtcNow
    & $ghPath release edit $tag --repo $GitHubRepository --draft=false --latest
    if ($LASTEXITCODE -ne 0) {
        $afterPublishRaw = & $ghPath release view $tag --repo $GitHubRepository --json isDraft 2>$null
        if ($LASTEXITCODE -ne 0 -or (ConvertFrom-Json -InputObject ($afterPublishRaw -join [Environment]::NewLine)).isDraft) {
            throw "No se pudo publicar el Release $tag. El binario queda en borrador para reintentar."
        }
    }
    $releasePublished = $true
    Write-Host "Release $tag publicado. Esperando a que Actions actualice manifest.json..."

    $deadline = [DateTimeOffset]::UtcNow.AddMinutes($ActionTimeoutMinutes)
    $workflowRun = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $runsRaw = & $ghPath api "repos/$GitHubRepository/actions/workflows/publish-manifest.yml/runs?event=release&per_page=20" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "No se pudieron consultar las ejecuciones de Actions: $($runsRaw -join ' ')" }
        $runs = ConvertFrom-Json -InputObject ($runsRaw -join [Environment]::NewLine)
        $workflowRun = @($runs.workflow_runs) |
            Where-Object { $_.event -eq 'release' -and ([DateTimeOffset]::Parse($_.created_at) -ge $releaseStarted.AddMinutes(-2)) } |
            Sort-Object -Property created_at -Descending |
            Select-Object -First 1
        if ($workflowRun -and $workflowRun.status -eq 'completed') {
            if ($workflowRun.conclusion -ne 'success') {
                throw "Falló el workflow OTA: $($workflowRun.html_url). El manifiesto anterior sigue activo."
            }
            break
        }
        Start-Sleep -Seconds 5
    }
    if (-not $workflowRun -or $workflowRun.status -ne 'completed') {
        throw "Release publicado; Actions sigue en curso o no inició. Revisa https://github.com/$GitHubRepository/actions/workflows/publish-manifest.yml"
    }

    $updatedManifest = Get-RemoteManifest -GhPath $ghPath -Repository $GitHubRepository
    if ([string]$updatedManifest.version -cne $version -or [string]$updatedManifest.url -cne $expectedAssetUrl) {
        throw "Actions terminó, pero manifest.json no apunta a $tag y $assetName. Revisa https://github.com/$GitHubRepository/actions/workflows/publish-manifest.yml"
    }
    Write-Host "Publicación completada: $tag"
    Write-Host "Manifiesto confirmado: $expectedAssetUrl"
    Write-Host 'El dispositivo descargará la actualización al iniciar o en su próxima revisión OTA automática.'
} catch {
    if ($versionFileChanged -and -not $releasePublished) {
        $tagExists = $false
        $releaseProbe = & $ghPath release view $tag --repo $GitHubRepository --json isDraft 2>$null
        if ($LASTEXITCODE -eq 0) { $tagExists = $true }
        if (-not $tagExists) {
            [System.IO.File]::WriteAllText($versionFile, $originalVersionContents, $utf8NoBom)
            Write-Warning 'Falló el proceso antes de crear un Release; restauré version.txt.'
        } else {
            Write-Warning "Conservé version.txt porque existe el borrador $tag; puede reintentarse con el mismo comando."
        }
    }
    throw
}