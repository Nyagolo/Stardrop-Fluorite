[CmdletBinding()]
param(
    [string]$Source,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$patcher = Join-Path $PSScriptRoot 'Updater\apply-stardrop-patch.ps1'
$options = @{ InstallDirectory = $PSScriptRoot; NoZip = $true }
if ($Source) { $options.Source = $Source }
if ($NoBuild) { $options.NoBuild = $true }
& $patcher @options
exit $LASTEXITCODE