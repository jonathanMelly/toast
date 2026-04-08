<#
.SYNOPSIS
    Installs BurntToast from the latest official GitHub Release (Stable & Lightweight).
#>

param (
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$Message,
    [Parameter(Mandatory=$false)][string]$ImagePath = "C:\ws\emacs.png",
    [Parameter(Mandatory=$false)][string]$AppID = "Microsoft.Windows.PowerShell"
)

function Show-FallbackMessageBox {
    param([string]$T, [string]$M)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($M, $T, 'OK', 'Information')
    } catch {
        Write-Host "CRITICAL: MessageBox failed. $_"
    }
}

function Install-From-Latest-Release {
    $tempZip = $null
    $extractPath = $null
    try {
        Write-Host ">>> Fetching latest release info from GitHub API..."
        $apiUrl = "https://api.github.com/repos/Windos/BurntToast/releases/latest"
        $releaseData = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        $version = $releaseData.tag_name
        Write-Host "Latest Release: $version"

        # Determine module path (PS5 vs PS7+)
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $moduleBase = "$HOME\Documents\PowerShell\Modules\BurntToast"
        } else {
            $moduleBase = "$HOME\Documents\WindowsPowerShell\Modules\BurntToast"
        }

        if (Test-Path $moduleBase) { Remove-Item -Recurse -Force $moduleBase }
        New-Item -ItemType Directory -Path $moduleBase -Force | Out-Null

        $tempZip   = "$env:TEMP\BurntToast_$version.zip"
        $extractPath = "$env:TEMP\BurntToast_Extracted_$PID"

        # Prefer a .zip release asset; fall back to zipball (source archive)
        $zipAsset = $releaseData.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        if ($zipAsset) {
            Write-Host "Downloading release asset: $($zipAsset.name)"
            Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
        } else {
            Write-Host "No zip asset found, downloading source zipball: $($releaseData.zipball_url)"
            Invoke-WebRequest -Uri $releaseData.zipball_url -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
        }

        Write-Host "Extracting..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $extractPath) { Remove-Item -Recurse -Force $extractPath }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $extractPath)

        # Resolve the actual module source directory.
        # - Proper zip asset: flat or one wrapper folder containing .psm1
        # - GitHub zipball: wrapper folder (Windos-BurntToast-<hash>/) with a BurntToast/ subfolder inside
        $sourceDir = $null
        $topFolders = @(Get-ChildItem -Path $extractPath -Directory)

        if ($topFolders.Count -eq 1) {
            $inner = Join-Path $topFolders[0].FullName "BurntToast"
            if (Test-Path $inner) {
                $sourceDir = $inner   # zipball layout
            } elseif (Get-ChildItem -Path $topFolders[0].FullName -Filter "*.psm1") {
                $sourceDir = $topFolders[0].FullName  # single-wrapper asset
            }
        }
        if (-not $sourceDir -and (Get-ChildItem -Path $extractPath -Filter "*.psm1")) {
            $sourceDir = $extractPath  # flat layout
        }
        if (-not $sourceDir) { throw "Could not locate BurntToast module files in the archive." }

        Write-Host "Copying from: $sourceDir"
        Get-ChildItem -Path $sourceDir | Copy-Item -Destination $moduleBase -Force -Recurse

        # Ensure .psm1 and .psd1 are named BurntToast.* (required by PowerShell module loader)
        foreach ($ext in "psm1","psd1") {
            $f = Get-ChildItem -Path $moduleBase -Filter "*.$ext" | Select-Object -First 1
            if ($f -and $f.BaseName -ne "BurntToast") {
                Write-Host "Renaming $($f.Name) -> BurntToast.$ext"
                Rename-Item -Path $f.FullName -NewName "BurntToast.$ext" -Force
            }
        }
        if (-not (Get-ChildItem -Path $moduleBase -Filter "*.psm1")) { throw "No .psm1 found after extraction." }

        Write-Host ">>> Installation Successful: $moduleBase (Version $version)"
        return $true
    }
    catch {
        Write-Error "Release installation failed: $_"
        return $false
    }
    finally {
        if ($tempZip    -and (Test-Path $tempZip))    { Remove-Item $tempZip    -Force -ErrorAction SilentlyContinue }
        if ($extractPath -and (Test-Path $extractPath)) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Install-Via-Gallery {
    try {
        Write-Host ">>> Trying Install-Module from PSGallery (CurrentUser)..."

        # PS5 defaults to TLS 1.0 which PSGallery rejects
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Ensure NuGet provider is present without interactive prompt
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]"2.8.5.201" })) {
            Write-Host "Installing NuGet provider..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
        }

        # Trust PSGallery for this session so no confirmation prompt blocks us
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        Install-Module -Name BurntToast -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host ">>> PSGallery install succeeded."
        return $true
    }
    catch {
        Write-Warning "PSGallery install failed: $_"
        return $false
    }
}

# --- MAIN LOGIC ---
try {
    $moduleName = "BurntToast"
    $module = Get-Module -ListAvailable -Name $moduleName

    if (-not $module) {
        Write-Warning "Module not found. Attempting install..."
        $success = Install-Via-Gallery
        if (-not $success) {
            Write-Warning "Falling back to GitHub Release zip..."
            $success = Install-From-Latest-Release
        }
        
        if (-not $success) {
            Show-FallbackMessageBox -T "Install Error" -M "Failed to install BurntToast from GitHub Release."
            exit 0
        }
        
        # Refresh cache modules
        $module = Get-Module -ListAvailable -Name $moduleName
        
        # If Get-Module still can't find it, add our install path to the search path
        if (-not $module) {
            if ($PSVersionTable.PSVersion.Major -ge 6) { $modParent = "$HOME\Documents\PowerShell\Modules" }
            else { $modParent = "$HOME\Documents\WindowsPowerShell\Modules" }

            if ($env:PSModulePath -notlike "*$modParent*") {
                $env:PSModulePath = "$modParent;$env:PSModulePath"
            }
            $module = Get-Module -ListAvailable -Name BurntToast
        }

        if (-not $module) { throw "Module still not found after installation." }
    }

    Write-Host "Importing module..."
    Import-Module BurntToast -Force -ErrorAction Stop

    # Verify at least one known command loaded
    $hasOldApi = [bool](Get-Command New-BTText -ErrorAction SilentlyContinue)
    $hasNewApi = [bool](Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue)
    if (-not $hasOldApi -and -not $hasNewApi) { throw "BurntToast loaded but no usable commands found - installation may be corrupt." }

    Write-Host "Sending notification (API: $(if ($hasNewApi) {'1.x'} else {'0.x'}))..."

    if ($hasNewApi) {
        # BurntToast 1.x API
        $cmdMeta = Get-Command New-BurntToastNotification
        $params  = @{ Text = @($Title, $Message) }
        if ($cmdMeta.Parameters.ContainsKey('AppId'))   { $params['AppId']   = $AppID }
        if ($cmdMeta.Parameters.ContainsKey('AppID'))   { $params['AppID']   = $AppID }
        if ((Test-Path $ImagePath) -and $cmdMeta.Parameters.ContainsKey('AppLogo')) { $params['AppLogo'] = $ImagePath }
        New-BurntToastNotification @params -ErrorAction Stop
    } else {
        # BurntToast 0.x builder API
        $icon = $null
        if (Test-Path $ImagePath) {
            try { $icon = New-BTImage -Source $ImagePath -AppLogoOverride -ErrorAction Stop }
            catch { Write-Warning "Image issue: $_" }
        }
        $content = New-BTContent -Visual (New-BTVisual -BindingGeneric (New-BTBinding -Children @(
            (New-BTText -Text $Title),
            (New-BTText -Text $Message)
        ) -AppLogoOverride $icon)) -Actions (New-BTAction -Buttons (New-BTButton -Dismiss -Content "Ok")) -Duration Long
        Submit-BTNotification -Content $content -AppID $AppID -ErrorAction Stop
    }

    Write-Host "SUCCESS: Toast displayed."
}
catch {
    Write-Error "Execution failed: $_"
    Show-FallbackMessageBox -T $Title -M $Message
}
exit 0