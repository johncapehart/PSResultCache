cd (Split-Path -Parent $MyInvocation.MyCommand.Path)
$moduleName = (gi (get-location)).Name
if (!(test-path function:\publish-module)) { . ..\gists\Publish-Module.ps1 }
$PSDefaultParameterValues.Clear()
{
    Select-Json 'build.json','build.secrets.json' -JsonPath "PSDefaultParameterValues" -AsPSDefaultParameterValues
    Publish-Module
}.Invoke();
