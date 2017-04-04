Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
$moduleName = select-json build.json, build.secrets.json -JsonPath 'PSDefaultParameterValues.Publish-Module.ModuleName'
$DebugPreference = 'SilentlyContinue'# silence noisy import-module
$VerbosePreference = 'SilentlyContinue'
$psISE.PowerShellTabs.Files | Where-Object IsSaved -ne $true | Where-Object DisplayName -match $moduleName | ForEach-Object { $_.Save() }
remove-module $moduleName -force -ErrorAction SilentlyContinue
Import-Module ".\$moduleName.psd1"
invoke-Pester
remove-module $moduleName -force -ErrorAction SilentlyContinue
