#
# This is a PowerShell Unit Test file.
# You need a unit test framework such as Pester to run PowerShell Unit tests.
# You can download Pester from http://go.microsoft.com/fwlink/?LinkID=534084
#
New-VariableFromJson PesterTests/tests.json,PesterTests/tests.secrets.json
$ttl = [TimeSpan]::Parse($testcache.ttl)
$testcache = New-Object PSCustomObject -Property $testcache
Describe 'Unit Tests' {
    Clear-PSResultCacheTestValues
    Clear-PSResultCache $testcache
    it 'Gets consistent values' {
        $v = Get-PSResultCache $testcache -Verbose
        $v.counter | should be 1
        $v = Get-PSResultCache $testcache -Verbose
        $v.counter | should be 1
    }
    it 'Gets updated values' {
        Start-Sleep -Seconds $ttl.TotalSeconds
        $v = Get-PSResultCache $testcache -Verbose
        $v.counter | should be 2
    }
}

Describe 'Service Tests' -Tags 'Service' {
    it 'Processes configurations in cache foder' {
        Update-PSResultCacheDirectory
        $date1 = (Get-CurrentPSResultCacheFile $testcache).LastWriteTime
        sleep -Seconds $ttl.TotalSeconds
        Update-PSResultCacheDirectory
        $date2 = (Get-CurrentPSResultCacheFile $testcache).LastWriteTime
        $span = ($date2 - $date1)
        write-verbose "Span $span ttl $ttl"
        $span.TotalSeconds | should BeGreaterThan 5
    }
}
<#

#>