# Makes sure NSIS (makensis.exe) is on the Windows runner, for building the installer.
# Chocolatey's package site sometimes times out (504), so: try it a few times, then download
# NSIS from SourceForge instead. Fails only when neither works.
$makensis = "C:\Program Files (x86)\NSIS\makensis.exe"
if (Test-Path $makensis) { Write-Host "NSIS is already installed"; exit 0 }

for ($try = 1; $try -le 3 -and -not (Test-Path $makensis); $try++) {
  Write-Host "Installing NSIS with Chocolatey (try $try of 3)"
  choco install nsis -y --no-progress
  if (-not (Test-Path $makensis)) { Start-Sleep -Seconds (20 * $try) }
}

if (-not (Test-Path $makensis)) {
  Write-Host "Chocolatey didn't work: downloading NSIS from SourceForge"
  $setup = Join-Path $env:RUNNER_TEMP "nsis-setup.exe"
  for ($try = 1; $try -le 3 -and -not (Test-Path $makensis); $try++) {
    curl.exe -fsSL --retry 3 -o $setup "https://downloads.sourceforge.net/project/nsis/NSIS%203/3.10/nsis-3.10-setup.exe"
    if ($LASTEXITCODE -eq 0) { Start-Process -FilePath $setup -ArgumentList "/S" -Wait }
    if (-not (Test-Path $makensis)) { Start-Sleep -Seconds 15 }
  }
}

if (-not (Test-Path $makensis)) { Write-Error "NSIS could not be installed"; exit 1 }
& $makensis /VERSION
