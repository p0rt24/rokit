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

function Add-RokitToPath {
    param([string]$BinPath)

    $regKey = 'HKCU:\Environment'

    # Читаем сырое значение из реестра (там может быть %USERPROFILE% без развёртки)
    $rawPath = (Get-ItemProperty -Path $regKey -Name 'PATH' -ErrorAction SilentlyContinue).PATH

    # Развёртываем для проверки — есть ли путь уже
    $expandedRaw = [Environment]::ExpandEnvironmentVariables($rawPath)

    if ($expandedRaw -like "*$BinPath*") {
        Write-Host "PATH уже содержит '$BinPath', пропускаем."
        return
    }

    # Записываем обратно с правильным типом REG_EXPAND_SZ,
    # чтобы %USERPROFILE% и другие переменные продолжали работать
    $newPath = if ($rawPath) { "$rawPath;$BinPath" } else { $BinPath }
    Set-ItemProperty -Path $regKey -Name 'PATH' -Value $newPath -Type ExpandString

    Write-Host "Добавлен '$BinPath' в PATH пользователя (реестр)."
}

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
        throw "rokit.exe не найден в распакованной директории"
    }

    Write-Host "[3 / 3] Running $PROGRAM_NAME self-install`n"
    Start-Process -FilePath ".\rokit\rokit.exe" -ArgumentList "self-install" -Wait -NoNewWindow

    # Гарантируем правильную запись в реестр и обновляем текущую сессию
    Add-RokitToPath -BinPath $ROKIT_BIN
    Update-SessionPath

    if (Get-Command rokit -ErrorAction SilentlyContinue) {
        Write-Host "`n✓ rokit установлен успешно!" -ForegroundColor Green
        rokit --version
    } else {
        Write-Warning "rokit не найден. Попробуйте перезапустить терминал."
    }
}
catch {
    Write-Error "Installation failed: $_"
    exit 1
}
finally {
    Remove-Item rokit.zip -ErrorAction SilentlyContinue
    Remove-Item .\rokit -Recurse -ErrorAction SilentlyContinue
    Set-Location $originalPath
}
