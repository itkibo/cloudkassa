<#

.SYNOPSIS

    This is core ps script to process data files
    It's a manager of all process: parsing, transforming and sending data to the ferma API ferma

.AUTHOR

    aleksandr h.

#>


Clear-Host

# superbasic
Set-Location $(Split-Path -Parent -Path $MyInvocation.MyCommand.Path)
$dirLog = ".\log"
$pathLog = "$dirLog\$(Get-Date -f 'yyyyMMdd-HHmmss-ff').txt"


# INCLUDE MODULES

# artisans
. ".\helpers\tiny-helper.ps1" # service functions
. ".\helpers\data-parser.ps1" # raw txt data parser + package processor
. ".\helpers\api-connector.ps1" # api ferma: auth, push...


# CONFIG + SCRIPT MODE

# script mode depends on detected config file name
# config rules:
# if .\debug.ini exists - enables DEBUG mode
# if .\debug.ini exists AND .\product.ini exists - enables DEBUG mode
# if .\product.ini exists only - enables PRODUCT mode
# if NO config - exit

# if debug config present, it is always overwrites other configs
if (Test-path -Path ".\debug.ini" -PathType Leaf) {

    # first of all get debug config
    if (!($cfgINI = Import-ini -Path ".\debug.ini")) { "exit. can not read config data" | Write-Log -e; exit }

    # script DEBUG mode enable
    $cfgIni.system.mode = $false
    $cfgIni.system.msg = @(
        'script D E B U G mode enabled'
        'will be used ferma-test api'
        $('-'*30)
    )

} elseif (Test-path -Path ".\product.ini" -PathType Leaf) {

    # in case debug config not present, try to get product config
    if (!($cfgINI = Import-ini -Path ".\product.ini")) { "exit. can not read config data" | Write-Log -e; exit }
    
    # script PRODUCT mode enable
    $cfgIni.system.mode = $true
    $cfgIni.system.msg = @(
        'script P R O D U C T mode enabled'
        'will be used real ferma api'
        $('-'*30)
    )

} else {

    "exit. no config file detected" | Write-Log -e; exit

} # // if..else

# ok, config has been read
$system = $cfgINI.system # system calculated config
$parser = $cfgINI.parser # parser parameters
$tree = $cfgINI.tree # script folders tree
$auth = $cfgINI.auth # api auth
$push = $cfgINI.push # api push

# iterate over sub folders in main source folder
# get package from each folder one by one
foreach ($SourceDir in Get-ChildItem -Path $tree.dirSource -Directory) {

    # SOME BASIC ACTIONS
    # source path with mask: \_source\sber\*.txt
    # if no source files - skip current folder, nothing to do
    $pathSourceFiles = "$($SourceDir.FullName)\*.txt"
    if (!(Test-path -Path $pathSourceFiles)) { Write-Host "skip current source folder. no source files $pathSourceFiles"; continue }

    # here is current package name
    [string]$PackageName = Get-Date -f 'yyyyMMdd-HHmmss-ff'

    # log file for current package = package name
    $pathLog = "$dirLog\$PackageName.txt"

    # check if stucked packages present, out warning message
    if ($StuckedPackages = Get-ChildItem -Path $tree.dirQueue -Directory) {
        @(
            $("-"*30)
            "WARN!"
            "stucked packages detected in a queue folder $($tree.dirQueue)"
            "stucked: $($StuckedPackages.Name -join ',')"
            "stucked packages do not affect new packages sending!"
            "to resolve this issue human assistance needed:"
            " > packages content should be analyzed"
            " > error receipts need to push again"
            " > if no errors then move them to $($tree.dirZip) and compress"
            $("-"*30)
        ) | Write-Log -e
    }

    # log current config name + script mode
    @(
        "current config file: $($system.filename)"
        $system.msg
    ) | Write-Log

    # get token, test if server available
    if (!($AuthToken = New-AuthToken @auth)) { "skip next procedures. can not get auth token" | Write-Log -e; continue }
    "auth token: $AuthToken" | Write-Log
    

    # NEW PACKAGE
    if (!($Package = New-Package -pathSourceFiles $pathSourceFiles -PackageName $PackageName -Mode $system.mode @tree)) { 
        "skip. can not create new package from source $pathSourceFiles" | Write-Log -e
        continue 
    }     

    # log basic package structure
    $Package | ConvertTo-JSON -Depth 3 | Out-File -FilePath $pathLog -Append -Encoding utf8

    # prepare receipts, result in .receipts property
    $Package = Get-PackageData -Package $Package @parser

    # push receipts, result in .transactions property, set package marker success = $true/$false
    $Package = Push-PackageData -Package $Package -AuthToken $AuthToken -paramsPush $push -paramsAuth $auth
   
    # export completed package to json file
    $Package | ConvertTo-JSON -Depth 10 | Out-File -FilePath "$($Package.result)\$($Package.name).json" -Encoding utf8

    # ANALYZING DATA
    # out package data to flat table file (flat table is sql table analog)
    ConvertTo-FlatTable -Package $Package -pathFile "$($Package.result)\$($Package.name).csv" -Encoding utf8


    # MOVE + COMPRESS
    Compress-Package -Package $Package


    # REPORTS
    Get-Reports -Package $Package

    'done', '-' | Write-Log 
    
} # // foreach ($SourceDir in $SourceDirectories)


# cleanup log folder
Get-ChildItem -Path $dirLog | Sort-Object -Property CreationTime -Descending | Select-Object -Skip 360 | Remove-Item -Force -ErrorAction SilentlyContinue
