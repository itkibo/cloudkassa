function Write-Log {

    # easy logger

    param(
        [parameter(ValueFromPipeline = $true)][string[]]$Message,
        [switch]$e,
        [string]$pathLog = $pathLog
    )

    process {
        $Message = "$(Get-Date -f 'yyyy-MM-dd-HHmmss')`t$Message"
        $Message | Out-File -FilePath $pathLog -Encoding utf8 -Append -Force -ErrorAction SilentlyContinue
        if ($e.IsPresent) { Write-Host $Message -ForegroundColor Red } else { Write-Host $Message -ForegroundColor Green }
    }

} # // Write-Log

function Import-ini {

    # imports ini file content as hashtable

    param(
        [string]$Path = $(Read-Host "please supply a value for the Path parameter")
    )

    $ini = @{}

    if (Test-Path -Path $Path) {

        switch -regex -file $Path
        {
            "^;|^#"
            {
                continue
            }
            "^\[(.+)\]$"
            {
                $Category = $matches[1]                
                $ini.$Category = @{}
            }
            "^(.+?)\s*=\s*['`"]?(.+?)['`"]?$"
            {            
                $Key,$Value = $matches[1..2]
                $ini.$Category.$Key = $Value
            }
        }
        
        # add system property
        $ini.Add('system', @{'filename' = Split-Path -Path $Path -Leaf})
        
        return $ini

    }
    else {

        Write-Host "file not found - $Path" 
        return $null

    }

} # // Import-Ini
