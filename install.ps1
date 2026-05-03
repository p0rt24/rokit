$PROGRAM_NAME = "rokit"
$REPOSITORY   = "rojo-rbx/rokit"
$ROKIT_BIN    = "$env:USERPROFILE\.rokit\bin"

$originalPath = Get-Location
Set-Location $env:TEMP

function Get-ReleaseInfo {
    param([string]$ApiUrl)
    $headers = @{ 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($env:GITHUB_PAT) { $headers['Authorization'] = "token $env:GITHUB_PAT" }
    try   { return Invoke-RestMethod -Uri $ApiUrl -Headers $headers -ErrorAction Stop }
    catch { throw "Failed to fetch release info: $_" }
}

# Читает актуальный PATH из реестра и применяет к текущей сессии
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = "$machine;$user"
}

try {
    if ($env:GITHUB_PAT) { Write-Host "NOTE: Using provided GITHUB_PAT for authentication" }

    Write-Host "`n[1 / 3] Looking for latest $PROGRAM_NAME release"
    $apiUrl      = "https://api.github.com/repos/$REPOSITORY/releases/latest"
    $releaseInfo = Get-ReleaseInfo -ApiUrl $apiUrl
    $versionTag  = $releaseInfo.tag_name
    $numericVer  = $versionTag -replace '^v', ''

    $downloadUrl = "https://github.com/$REPOSITORY/releases/download/$versionTag/$PROGRAM_NAME-$numericVer-windows-x86_64.zip"
    Write-Host "[2 / 3] Downloading '$PROGRAM_NAME-$numericVer-windows-x86_64.zip'"

    Invoke-WebRequest $downloadUrl -OutFile rokit.zip -ErrorAction Stop
    Expand-Archive -Path rokit.zip -DestinationPath .\rokit -Force -ErrorAction Stop

    if (-not (Test-Path ".\rokit\rokit.exe")) {
        throw "rokit.exe not found in the extracted directory"
    }

    Write-Host "[3 / 3] Running $PROGRAM_NAME self-install`n"
    Start-Process -FilePath ".\rokit\rokit.exe" -ArgumentList "self-install" -Wait -NoNewWindow

    # ── КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ ──────────────────────────────────────────────────
    # self-install прописывает путь в реестр, но текущая сессия и новые сессии
    # могут его не подхватить. Принудительно добавляем и обновляем.

    $curUserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($curUserPath -notlike "*$ROKIT_BIN*") {
        [Environment]::SetEnvironmentVariable(
            'PATH',
            "$curUserPath;$ROKIT_BIN",
            'User'
        )
        Write-Host "Added '$ROKIT_BIN' to user PATH"
    }

    # Применяем новый PATH к текущей сессии (без этого rokit не виден до перезапуска)
    Update-SessionPath
    # ─────────────────────────────────────────────────────────────────────────

    if (Get-Command rokit -ErrorAction SilentlyContinue) {
        Write-Host "`n✓ rokit установлен и уже доступен в этой сессии!" -ForegroundColor Green
        rokit --version
    } else {
        Write-Warning "rokit не найден в PATH после установки. Перезапустите терминал."
    }
}
catch {
    Write-Error "Installation failed: $_"
    exit 1
}
finally {
    Remove-Item rokit.zip      -ErrorAction SilentlyContinue
    Remove-Item .\rokit -Recurse -ErrorAction SilentlyContinue
    Set-Location $originalPath
}
