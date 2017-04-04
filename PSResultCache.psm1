$modulePath = $PSScriptRoot
write-verbose "Importing variables from $modulePath/lib/secrets.json"
New-VariableFromJson "$modulePath/lib/defaults.json", "$modulePath/lib/secrets.json"
[Console]::WriteLine("Module loading from $modulePath $cachepath $serviceinterval")
function Set-PSResultCachedValue {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache,
        $value,
        $date
    )
    $cache.value = $value
    if ($date -eq $null -and $value -ne $null) {
        $date = Get-Date
    }
    $cache.timestamp = $date
}

function Get-PSResultCachedValue {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    $cache.value
}

function Get-PSResultCacheDate {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    $cache.timestamp
}

function Get-PSResultCacheTtl {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    if ($cache.ttl -isnot [TimeSpan]) {
        $cache.ttl = [TimeSpan]::Parse($cache.ttl)
    }
    $cache.ttl
}

function Get-PSResultCacheFiles {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    if (![string]::IsNullOrEmpty($cachepath) -and (Test-Path $cachepath)) {
        Get-ChildItem ([IO.Path]::Combine($cachepath , $cache.filepattern)) | where Name -notmatch 'config.json$' | sort LastWriteTime -Descending
    }
}

function Get-CurrentPSResultCacheFile {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    Get-PSResultCacheFiles $cache | select -First 1
}

function Get-NextPSResultCacheFile {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    [IO.Path]::Combine($cachepath , ($cache.filepattern -replace [Regex]::Escape('*'), (Get-Date -format yyyyMMdd-HHmmss)))
}

function Optimize-PSResultCache {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    Get-PSResultCacheFiles $cache | select -skip 2 | Remove-item
}

function Clear-PSResultCache {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    Get-PSResultCacheFiles $cache | Remove-Item
    Set-PSResultCachedValue $cache $null
}

function Test-PSResultMemoryCache {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    $ttl = Get-PSResultCacheTtl $cache
    $date = Get-PSResultCacheDate $cache
    $v = Get-PSResultCachedValue $cache
    if ($date -eq $null -or $v -eq $null) {
        Write-Verbose "Memory cache $($cache.name) is empty"
        return $false;
    } else {
        $span = (Get-Date) - $date
        $span = [TimeSpan]::FromSeconds([Math]::Round($span.TotalSeconds))
        Write-Verbose "Memory cache $($cache.name) ttl $ttl age $span $(@{$true='out of date';$false=''}[$span -ge $ttl])"
        return $span -lt $ttl
    }
}

function Test-PSResultDiskCache {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    $f = Get-CurrentPSResultCacheFile $cache
    if ($f) {
        $ttl = Get-PSResultCacheTtl $cache
        $date = $f.LastWriteTime
        $span = (Get-Date) - $date
        $span = [TimeSpan]::FromSeconds([Math]::Round($span.TotalSeconds))
        write-verbose "Cache file $($f.name) $date ttl $ttl $($ttl.TotalSeconds) age $span $(@{$true='out of date';$false=''}[$span -ge $ttl])"
        return $span -lt $ttl
    } else {
        write-verbose "Cache file not found for $($cache.name)"
        return $false
    }
}

function Update-PSResultCacheFile {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    write-verbose "Getting values from $($cache.getterfunction)"
    $v = [ScriptBlock]::Create("$($cache.getterfunction)").Invoke()
    if ($v -eq $null) {
        $v = New-Object PSCustomObject
    }
    if (!(Test-Path $cachepath)) { mkdir $cachepath }
    $f = Get-NextPSResultCacheFile $cache
    write-verbose "Saving file $f"
    $v | ConvertTo-Json | Set-Content $f -Encoding UTF8 -Force
    Set-PSResultCachedValue $cache $v
    Optimize-PSResultCache $cache
}

function Get-PSResultCache {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCustomObject]$cache
    )
    try {
        if ((Test-PSResultMemoryCache $cache)) {
            return Get-PSResultCachedValue $cache
        }
        if ((Test-PSResultDiskCache $cache)) {
            $f = Get-CurrentPSResultCacheFile $cache
            write-verbose "Reading file $f"
            Set-PSResultCachedValue $cache (Get-Content $f -raw | ConvertFrom-Json) $lastWriteTime
            $f.LastAccessTime = (Get-Date)
            return Get-PSResultCachedValue $cache
        }
    } catch {
        Set-PSResultCachedValue $cache $null
        Write-Warning ($_ | out-string)
    }
    Update-PSResultCacheFile $cache
    return Get-PSResultCachedValue $cache
}

function Update-PSResultCacheDirectory {
    [CmdletBinding()]param(
    )
    if ((Test-Path $cachepath)) {
        $l = Get-ChildItem ([IO.Path]::Combine($cachepath , '*.config.json')) | sort Name
        $l | % {
            try {
                $cache = gc -Path $_ -Raw | convertfrom-json
                if (!(Test-PSResultDiskCache $cache)) {
                    [Console]::WriteLine("Update-PSResultCacheDirectory $($cache.name)")
                    Update-PSResultCacheFile $cache
                    $log = $cache | select name, filepattern, getterfunction,
                    @{
                        n='ttl';e={ '{0:c}' -f $_.ttl }
                    },
                    @{
                        n='timestamp';e={ Get-Date $_.timestamp -Format s }
                    },
                    @{
                        n='value';e={ $_.value.GetType().Name }
                    }
                    Add-Content -Path ([IO.Path]::Combine($cachepath , 'cache.log')) -value ($log | convertto-json -Compress) -Force
                }
            } catch {
                Write-Warning ($_ | out-string)
            }
        }
    }
}

$script:PSResultCacheTestCounter = 0
function Clear-PSResultCacheTestValues {
    $script:PSResultCacheTestCounter = 0
}

function Get-PSResultCacheTestValues {
    $script:PSResultCacheTestCounter++
    new-object PSCustomObject -Property @{'counter'=$script:PSResultCacheTestCounter}
}


function Update-PSResultCacheDirectoryForever {
    [CmdletBinding()]param(
    )
    if (!(Test-Path $cachepath)) { mkdir $cachepath }
    $ttl = [TimeSpan]::Parse($serviceinterval)
    $log = New-Object PSCustomObject -Property @{'path'=$cachepath;'ttl'=('{0:c}' -f $ttl)}
    Add-Content -Path ([IO.Path]::Combine($cachepath , 'cache.log')) -value ($log | convertto-json -Compress) -Force
    while ($true) {
        try {
            Update-PSResultCacheDirectory
            Start-Sleep -Seconds $ttl.TotalSeconds
        } catch {
            Write-Warning ($_ | out-string)
            Start-Sleep -Seconds 900
        }
    }
}


function Install-PSResultCacheService {
    [CmdletBinding()]param(
    )
    invoke-expression "nssm install 'PSResultCacheService' 'powershell.exe' '-Command {Update-PSResultCacheDirectoryForever}'"
    Start-Service PSResultCacheService
}
