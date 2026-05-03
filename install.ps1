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

# Гарантируем наличие пути в реестре (REG_EXPAND_SZ, чтобы %USERPROFILE% работал)
function Add-ToUserPath {
    param([string]$BinPath)
    $regKey  = 'HKCU:\Environment'
    $rawPath = (Get-ItemProperty -Path $regKey -Name 'PATH' -ErrorAction SilentlyContinue).PATH
    $expanded = [Environment]::ExpandEnvironmentVariables($rawPath)
    if ($expanded -like "*$BinPath*") {
        Write-Host "PATH уже содержит '$BinPath'"
        return
    }
    $newPath = if ($rawPath) { "$rawPath;$BinPath" } else { $BinPath }
    Set-ItemProperty -Path $regKey -Name 'PATH' -Value $newPath -Type ExpandString
    Write-Host "Добавлен '$BinPath' в PATH пользователя"
}

# Рассылает WM_SETTINGCHANGE — все процессы (включая новые PowerShell) подхватят новый PATH
function Broadcast-EnvChange {
    $sig = @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $type   = Add-Type -MemberDefinition $sig -Name WinEnv -Namespace Win32 -PassThru -ErrorAction SilentlyContinue
    $result = [UIntPtr]::Zero
    # HWND_BROADCAST=0xFFFF, WM_SETTINGCHANGE=0x1A, SMTO_ABORTIFHUNG=0x2
    $type::SendMessageTimeout(0xFFFF, 0x1A, [UIntPtr]::Zero, "Environment", 0x2, 5000, [ref]$result) | Out-Null
    Write-Host "WM_SETTINGCHANGE разослан — новые сессии подхватят PATH"
}

# Обновляет PATH прямо в текущей сессии
function Update-SessionPath {
    $machine  = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user     = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = "$machine;$user"
}

try {
    if ($env:GITHUB_PAT) { Write-Host "NOTE: Using provided GITHUB_PAT for authentication" }

    Write-Host "`n[1 / 3] Looking for latest $PROGRAM_NAME release"
    $releaseInfo = Get-ReleaseInfo -ApiUrl "https://api.github.com/repos/$REPOSITORY/releases/latest"
    $versionTag  = $releaseInfo.tag_name
    $numericVer  = $versionTag -replace '^v', ''

    $downloadUrl = "https://github.com/$REPOSITORY/releases/download/$versionTag/$PROGRAM_NAME-$numericVer-windows-x86_64.zip"
    Write-Host "[2 / 3] Downloading '$PROGRAM_NAME-$numericVer-windows-x86_64.zip'"

    Invoke-WebRequest $downloadUrl -OutFile rokit.zip -ErrorAction Stop
    Expand-Archive -Path rokit.zip -DestinationPath .\rokit -Force -ErrorAction Stop

    if (-not (Test-Path ".\rokit\rokit.exe")) { throw "rokit.exe не найден в архиве" }

    Write-Host "[3 / 3] Running $PROGRAM_NAME self-install`n"
    Start-Process -FilePath ".\rokit\rokit.exe" -ArgumentList "self-install" -Wait -NoNewWindow

    # Страховка: если self-install не прописал путь — прописываем сами
    Add-ToUserPath -BinPath $ROKIT_BIN

    # Уведомляем Windows → все новые сессии увидят обновлённый PATH
    Broadcast-EnvChange

    # Применяем к текущей сессии
    Update-SessionPath

    if (Get-Command rokit -ErrorAction SilentlyContinue) {
        Write-Host "`n✓ Готово! rokit доступен и в этой сессии, и в новых." -ForegroundColor Green
        Write-Host "`up" -ForegroundColor Green
        rokit --version
    } else {
        Write-Warning "rokit не найден даже после обновления PATH. Проверьте вручную: '$ROKIT_BIN'"
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
