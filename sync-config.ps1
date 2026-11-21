<#
.SYNOPSIS
    Sync Klipper/Moonraker configuration files between this repo and the Sovol SV08 Max.

.DESCRIPTION
    Manages pushing configs from home/sovol/printer_data/config/ to the printer,
    pulling live configs into home/sovol-live/printer_data/config/, diffing against
    the live printer, and setting up passwordless SSH key authentication.

.EXAMPLE
    .\sync-config.ps1 setup-ssh
    .\sync-config.ps1 diff
    .\sync-config.ps1 push
    .\sync-config.ps1 push -DryRun
    .\sync-config.ps1 pull
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("push", "pull", "diff", "setup-ssh")]
    [string]$Action,

    [string]$PrinterIp = $(if ($env:SV08_IP) { $env:SV08_IP } else { "192.168.50.201" }),
    [string]$User = "sovol",
    [switch]$DryRun,
    [switch]$NoRestart,
    [switch]$ForcePrinterCfg,
    [switch]$ForceRestart
)

$ErrorActionPreference = "Stop"

$LocalConfigDir = Join-Path $PSScriptRoot "home\sovol\printer_data\config"
$LiveMirrorDir  = Join-Path $PSScriptRoot "home\sovol-live\printer_data\config"
$RemoteConfigDir = "/home/$User/printer_data/config"
$SshTarget = "$User@$PrinterIp"
$SaveConfigMarker = "#*# <---------------------- SAVE_CONFIG ---------------------->"

# Files owned by runtime state or symlinks on the printer; never overwrite during push
$PushExcludeFiles = @(
    "saved_variables.cfg",
    "moonraker.conf.backup",
    "printer-backup.cfg",
    "mainsail.cfg",
    "moonraker_obico_macros.cfg",
    "timelapse.cfg"
)

function Assert-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Split-SaveConfig {
    param([string]$Content)
    $normalized = $Content -replace "`r`n", "`n"
    $idx = $normalized.IndexOf($SaveConfigMarker)
    if ($idx -lt 0) {
        return @{ Body = $normalized.TrimEnd("`n") + "`n"; Footer = "" }
    }
    $body = $normalized.Substring(0, $idx).TrimEnd("`n") + "`n"
    $footer = $normalized.Substring($idx).TrimEnd("`n") + "`n"
    return @{ Body = $body; Footer = $footer }
}

function Get-PushFiles {
    Get-ChildItem -Path $LocalConfigDir -File | Where-Object {
        ($_.Extension -in @(".cfg", ".conf")) -and
        ($PushExcludeFiles -notcontains $_.Name) -and
        ($_.Name -notmatch '^printer-\d{8}_\d{6}\.cfg$')
    }
}

function Invoke-SetupSsh {
    $sshDir = Join-Path $HOME ".ssh"
    $keyPath = Join-Path $sshDir "id_ed25519"
    $pubPath = "$keyPath.pub"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    if (-not (Test-Path $pubPath)) {
        Write-Host "Generating ED25519 SSH key at $keyPath..." -ForegroundColor Cyan
        & ssh-keygen -t ed25519 -f $keyPath -N '""'
        if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed." }
    } else {
        Write-Host "Using existing SSH public key: $pubPath" -ForegroundColor Cyan
    }

    $pubKey = (Get-Content $pubPath -Raw).Trim()
    Write-Host "Installing public key on $SshTarget (you will be prompted for the '$User' password once)..." -ForegroundColor Yellow
    $remoteCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$pubKey' ~/.ssh/authorized_keys 2>/dev/null || echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    & ssh $SshTarget $remoteCmd
    if ($LASTEXITCODE -ne 0) { throw "Failed to install SSH key on $SshTarget." }

    Write-Host "SSH key installed. Future sync commands should not prompt for a password." -ForegroundColor Green
}

function Invoke-Pull {
    if (-not (Test-Path $LiveMirrorDir)) {
        New-Item -ItemType Directory -Path $LiveMirrorDir -Force | Out-Null
    }
    Write-Host "Pulling live configs from ${SshTarget}:$RemoteConfigDir -> $LiveMirrorDir" -ForegroundColor Cyan
    & scp "${SshTarget}:$RemoteConfigDir/*.cfg" "${SshTarget}:$RemoteConfigDir/*.conf" "$LiveMirrorDir/"
    if ($LASTEXITCODE -ne 0) { throw "scp pull failed." }
    Write-Host "Pull complete. Run 'git status' or 'git diff home/sovol-live/printer_data/config' to inspect changes." -ForegroundColor Green
}

function Invoke-Diff {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sv08_diff_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        Write-Host "Fetching live configs from $SshTarget for comparison..." -ForegroundColor Cyan
        & scp -q "${SshTarget}:$RemoteConfigDir/*.cfg" "${SshTarget}:$RemoteConfigDir/*.conf" "$tempDir/"
        if ($LASTEXITCODE -ne 0) { throw "Failed to fetch remote configs." }

        $files = Get-PushFiles
        $anyDiff = $false

        foreach ($file in $files) {
            $remoteFile = Join-Path $tempDir $file.Name
            if (-not (Test-Path $remoteFile)) {
                Write-Host "[NEW] $($file.Name) (exists locally, not on printer)" -ForegroundColor Yellow
                $anyDiff = $true
                continue
            }

            $localText = (Get-Content $file.FullName -Raw) -replace "`r`n", "`n"
            $remoteText = (Get-Content $remoteFile -Raw) -replace "`r`n", "`n"

            if ($file.Name -eq "printer.cfg" -and -not $ForcePrinterCfg) {
                $localParts = Split-SaveConfig $localText
                $remoteParts = Split-SaveConfig $remoteText
                if ($localParts.Body -ne $remoteParts.Body) {
                    $anyDiff = $true
                    Write-Host "`n=== DIFF: printer.cfg (excluding SAVE_CONFIG footer) ===" -ForegroundColor Yellow
                    $lTmp = Join-Path $tempDir "local_printer_body.cfg"
                    $rTmp = Join-Path $tempDir "remote_printer_body.cfg"
                    [System.IO.File]::WriteAllText($lTmp, $localParts.Body, [System.Text.UTF8Encoding]::new($false))
                    [System.IO.File]::WriteAllText($rTmp, $remoteParts.Body, [System.Text.UTF8Encoding]::new($false))
                    & git diff --no-index -- $rTmp $lTmp
                }
                if ($localParts.Footer -ne $remoteParts.Footer) {
                    Write-Host "[INFO] printer.cfg SAVE_CONFIG footer differs from local (will be preserved from printer on push)." -ForegroundColor DarkGray
                }
            } elseif ($localText -ne $remoteText) {
                $anyDiff = $true
                Write-Host "`n=== DIFF: $($file.Name) ===" -ForegroundColor Yellow
                $lTmp = Join-Path $tempDir ("local_" + $file.Name)
                [System.IO.File]::WriteAllText($lTmp, $localText, [System.Text.UTF8Encoding]::new($false))
                & git diff --no-index -- $remoteFile $lTmp
            }
        }

        if (-not $anyDiff) {
            Write-Host "No differences found between local config and live printer." -ForegroundColor Green
        }
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-PrinterIdle {
    try {
        $resp = Invoke-RestMethod -Method Get -Uri "http://${PrinterIp}:7125/printer/objects/query?print_stats" -TimeoutSec 5
        $state = $resp.result.status.print_stats.state
        if ($state -in @("printing", "paused")) {
            return $state
        }
        return $null
    } catch {
        Write-Warning "Could not query Moonraker print state: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-Push {
    $files = Get-PushFiles
    if ($files.Count -eq 0) {
        throw "No config files found in $LocalConfigDir"
    }

    $stageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sv08_push_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

    try {
        # Fetch live printer.cfg so we can preserve its SAVE_CONFIG calibration block
        $remotePrinterCfgPath = Join-Path $stageDir "remote_printer.cfg"
        $hasRemotePrinterCfg = $false
        if (-not $ForcePrinterCfg) {
            & scp -q "${SshTarget}:$RemoteConfigDir/printer.cfg" $remotePrinterCfgPath 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $remotePrinterCfgPath)) {
                $hasRemotePrinterCfg = $true
            }
        }

        $uploadList = @()
        foreach ($file in $files) {
            $destPath = Join-Path $stageDir $file.Name
            $content = (Get-Content $file.FullName -Raw) -replace "`r`n", "`n"

            if ($file.Name -eq "printer.cfg" -and -not $ForcePrinterCfg -and $hasRemotePrinterCfg) {
                $localParts = Split-SaveConfig $content
                $remoteParts = Split-SaveConfig (Get-Content $remotePrinterCfgPath -Raw)
                if ($remoteParts.Footer) {
                    $content = $localParts.Body + "`n" + $remoteParts.Footer
                    Write-Host "Preserving live printer SAVE_CONFIG block in printer.cfg." -ForegroundColor DarkCyan
                }
            }

            [System.IO.File]::WriteAllText($destPath, $content, [System.Text.UTF8Encoding]::new($false))
            $uploadList += $destPath
        }

        if ($DryRun) {
            Write-Host "[DRY RUN] Would back up remote configs and upload $($uploadList.Count) files to ${SshTarget}:$RemoteConfigDir" -ForegroundColor Yellow
            $files | ForEach-Object { Write-Host "  - $($_.Name)" }
            return
        }

        Write-Host "Creating safety backup on printer at ~/printer_data/.sync_backup/..." -ForegroundColor Cyan
        & ssh $SshTarget "mkdir -p ~/printer_data/.sync_backup && cp -a $RemoteConfigDir/*.cfg $RemoteConfigDir/*.conf ~/printer_data/.sync_backup/ 2>/dev/null || true"
        if ($LASTEXITCODE -ne 0) { throw "Remote backup step failed." }

        Write-Host "Uploading $($uploadList.Count) config files to ${SshTarget}:$RemoteConfigDir..." -ForegroundColor Cyan
        & scp @uploadList "${SshTarget}:$RemoteConfigDir/"
        if ($LASTEXITCODE -ne 0) { throw "scp upload failed." }

        Write-Host "Upload complete." -ForegroundColor Green

        if (-not $NoRestart) {
            $activeState = Test-PrinterIdle
            if ($activeState -and -not $ForceRestart) {
                Write-Warning "Printer is currently '$activeState'. Skipping Klipper restart (use -ForceRestart to override)."
                return
            }

            Write-Host "Restarting Klipper firmware via Moonraker..." -ForegroundColor Cyan
            Invoke-RestMethod -Method Post -Uri "http://${PrinterIp}:7125/printer/firmware_restart" -TimeoutSec 10 | Out-Null
            Write-Host "Klipper firmware restart requested." -ForegroundColor Green
        }
    } finally {
        Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Command "ssh"
Assert-Command "scp"

switch ($Action) {
    "setup-ssh" { Invoke-SetupSsh }
    "pull"      { Invoke-Pull }
    "diff"      { Invoke-Diff }
    "push"      { Invoke-Push }
}
