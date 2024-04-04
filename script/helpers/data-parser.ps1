function ConvertTo-StructuredHashData {

    # read all data from txt file, return structured object

    param (
        [string]$pathSourceFile
    ) 

    # read raw data file into array
    if (!($fileContent = Get-Content $pathSourceFile)) { return $null }

    # result structure
    $htResult = @{
        'data' = $null
        'filetype' = $null
        'filename' = Split-Path -Path $pathSourceFile -Leaf
    }
    
    # detect source file type depends on file header
    if ($fileContent[0] -eq '1CClientBankExchange') { 

        # bank statement type: sber or gbp
        for ($ItemIndex = 0; $ItemIndex -le $fileContent.Count - 1; $ItemIndex++) {

            $strRow = $fileContent[$ItemIndex]
            $KeyValue = $strRow -split '='

            # specify file type
            if ($KeyValue[0] -eq 'РасчСчет') {

                if ($KeyValue[1] -eq '00000000000000000001') { 
                    $htResult.filetype = 'BankStatementGpb'
                } 
                else { 
                    $htResult.filetype = 'BankStatementSber'
                }

                # not need to read all other data
                break

            } # // if ($KeyValue[0] -eq 'РасчСчет')
    
        } # // for detetect file type

    } elseif ($fileContent[0][0] -eq '#') {
        # sber registry type
        $htResult.filetype = 'BankRegistrySber'
    } else {
        # unknown type
        return $null
    }

    # lst array of docs, each item contains hashtable with doc structure
    $lstDocs = [System.Collections.ArrayList]@()
    
    # iterate over strings in array in strict order as is in source file
    for ($ItemIndex = 0; $ItemIndex -le $fileContent.Count - 1; $ItemIndex++) {

        $strRow = $fileContent[$ItemIndex]
        if (!$strRow -or $strRow -eq '') { continue }

        if ($htResult.filetype -eq 'BankRegistrySber') {

            # bank registry .txt file structure like a csv, values delimited ; symbol

            # skip header or commented row
            if ($strRow[0] -eq '#') { continue }
            
            # doc data
            $ArrValues = $strRow -split ';'

            # get only needed values
            $htDocData = @{
                'Плательщик'= $ArrValues[1]
                'Сумма'= $ArrValues[3]
                'ПлательщикРасчСчет' = ''
            }

            # collect
            $lstDocs.Add($htDocData) > $null
            $htDocData = $null

        } else {
            
            # bank statement .txt file structure like an ini config file
            # key = value pair in each row
            # doc starts with marker 'СекцияДокумент=Платежное поручение', ends with 'КонецДокумента'

            # doc starts
            if ($strRow -eq 'СекцияДокумент=Платежное поручение') { $htDocData = @{} }

            # fill with data
            if ($htDocData) {

                $KeyValue = $strRow -split '='

                # get only needed values
                if ($KeyValue[0] -in ('Плательщик', 'Сумма', 'ПлательщикРасчСчет')) {
                    $htDocData.Add($KeyValue[0], $KeyValue[1])
                }
                
                # gbp contains key 'Плательщик1' instead 'Плательщик', replace key
                if ($KeyValue[0] -eq 'Плательщик1') {
                    $htDocData.Add('Плательщик', $KeyValue[1])
                }

            }

            # collect
            if (($strRow -eq 'КонецДокумента') -and $htDocData) { 
                $lstDocs.Add($htDocData) > $null
                $htDocData = $null
            }

        } # // if

    } # // for

    $htResult.data = $lstDocs

    return $htResult

} # // ConvertTo-StructuredHashData

function Test-Document {
    
    # test document data: human\other

    param (
        [hashtable]$Document,
        [array]$ExcludeStrings
    )
    
    # exclude by exact value in exclude list
    if ($Document['Плательщик'] -in $ExcludeStrings) { return $false }

    # exclude by regex pattern
    if ( $Document['ПлательщикРасчСчет'] -notmatch '^408877|^303322144|^322|^555|^4433|^5599' ) { return $false }

    return $true

} # // Test-Document

function Split-FileData {

    # split humans/others, return arrays, save into a file if needed

    param (
        [hashtable]$fileData,
        [array]$ExcludeStrings, # array of organisations to exclude
        [string]$dirDestination # if present then save result into
    )

    # array lists humans/others
    $lstHumans = [System.Collections.ArrayList]@()
    $lstOthers = [System.Collections.ArrayList]@()
    
    if ($fileData.filetype -eq 'BankRegistrySber') {

        # split not needed for bank registry file type
        $lstHumans = $fileData.data 

    } else {

        # split is needed only for bank statement file type
        for ($indexItem=0; $indexItem -le $fileData.data.count - 1; $indexItem++) {

            $Doc = $fileData.data[$indexItem]
            if (Test-Document -Document $Doc -ExcludeStrings $ExcludeStrings) { $lstHumans.Add($Doc) > $null } else { $lstOthers.Add($Doc) > $null }

        }

    } # // if ... else

    # save splitted result into a separate files for users check
    if ($dirDestination -and (Test-Path -Path $dirDestination -PathType Container)) {

        # file paths
        $pathHumans = "$dirDestination\$($fileData.filename.Replace(".txt", "-KKT.txt"))"
        $pathOthers = "$dirDestination\$($fileData.filename.Replace(".txt", "-others.txt"))"

        $lstHumans | % {
            $strRow = "{0};{1};{2}" -f $_['Плательщик'], $_['ПлательщикРасчСчет'], $_['Сумма']
            $strRow | Out-File -FilePath $pathHumans -Encoding utf8 -Append
        }
        $lstOthers | % {
            $strRow = "{0};{1};{2}" -f $_['Плательщик'], $_['ПлательщикРасчСчет'], $_['Сумма']
            $strRow | Out-File -FilePath $pathOthers -Encoding utf8 -Append
        }

    } # // if

    return @{humans = $lstHumans; others = $lstOthers}

} # // Split-FileData

function New-Package {

    # grab files from source dir
    # create ht basic structure of package
    # create necessary folders tree

    param (
        [string]$pathSourceFiles, # input users folder
        [string]$PackageName,
        [bool]$Mode, # script mode
        [string]$dirQueue, # internal script queue folder
        [string]$dirZip, # internal script zip folder
        [string]$dirReport # output users reports folder
    )
    
    # grab source directory content, create a package from source files
    "new package name: $PackageName" | Write-Log

    $Package = @{
        'files' = @() # array of source file paths
        'filescount' = 0
        'name' = $PackageName
        'mode' = $(if ($Mode -eq $true) { 'production '} else { 'debug' })
        'package' = "$dirQueue\$PackageName" # package processing queue folder
        'source' = "$dirQueue\$PackageName\source" # example: queue\packagename\source
        'result' = "$dirQueue\$PackageName\result" # example: queue\packagename\result
        'zip' = $dirZip # archived packages root folder
        'report' = "$dirReport\$PackageName" # package report folder example: _report\packagename\
    }

    # create package necessary folders tree
    if (!(New-Item -Path $Package.source -ItemType Directory -Force)) { return $false }
    if (!(New-Item -Path $Package.result -ItemType Directory -Force)) { return $false } 
    if (!(New-Item -Path $Package.zip -ItemType Directory -Force)) { return $false } 

    # create package report folder
    New-Item -Path $Package.report -ItemType Directory -Force > $null

    foreach ($SourceFile in Get-ChildItem -Path $pathSourceFiles) {

        if ($SourceFile.Length -eq 0) {
            "skip. source file length = 0 $($SourceFile.FullName)" | Write-Log -e
            continue
        }

        # move file into a package
        if (Move-Item -Path $SourceFile -Destination $Package.source -Force -PassThru) {
            $Package.files += $SourceFile.FullName
            $Package.filescount++
        } else {
            "skip. can not move file $($SourceFile.FullName) from source" | Write-Log -e
            continue
        }
        
    } # // foreach

    if ($Package.filescount -gt 0) { return $Package }
    else {
        "nothing to process. there are no files grabbed into a package" | Write-Log
        return $false 
    }

} # // New-Package

function Get-PackageData {

    # returns array of receipts
    # result into .data property

    param(
        [hashtable]$Package,
        [string]$pathReceiptTemplate,
        [string]$pathExcludeOrgList
    )

    # read exclude organizations list (used for bank statement file type only)
    [array]$ExcludeStrings = @()
    if (Test-path -Path $pathExcludeOrgList) { [array]$ExcludeStrings = Get-Content -Path $pathExcludeOrgList -Encoding UTF8 }

    # array list contains complete information about receipts 
    $packData = [System.Collections.ArrayList]@()
    
    "package $($Package.name) processing..." | Write-Log

    # iterate over source files in current package
    foreach ($SourceFile in Get-ChildItem -Path $Package.source) {
        
        " > source file: $($SourceFile.Name)" | Write-Log

        # get full content as hashtable
        if (!($fileData = ConvertTo-StructuredHashData -pathSourceFile $SourceFile.FullName)) {
            "error, can not get data from source file" | Write-Log -e
            continue
        }
        " > file type: $($fileData.filetype)" | Write-Log

        # split data humans/others, save report for user into dirDestination folder
        $htSplitted = Split-FileData -fileData $fileData -ExcludeStrings $ExcludeStrings -dirDestination $Package.report
        $lstHumans = $htSplitted.humans
        " > docs counter human/other/total: $($lstHumans.count)/$($htSplitted.others.count)/$($fileData.data.count)" | Write-Log

        " > receipts count: $($lstHumans.count) preparing..." | Write-Log
        $lstReceipts = [System.Collections.ArrayList]@()

        # iterate over humans list, add receipts into collection
        for ($ItemIndex = 0; $ItemIndex -le $lstHumans.count - 1; $ItemIndex++) {

            [hashtable]$Doc = $lstHumans[$ItemIndex]
            $DocNum = $ItemIndex + 1

            # get receipt structure with default values from json file
            # each ObjReceipt contains htable based on only one unique receipt = doc in source file
            $ObjRequest = Get-Content -Path $pathReceiptTemplate -Raw -Encoding UTF8 | ConvertFrom-JSON

            # date time when receipt created on our side
            $ReceiptTimeStamp = Get-Date

            # unique receipt id on our side: packagename@receiptcreatetimestamp@receiptordernumber
            [string]$InvoiceId = "{0}@{1}@{2:d6}" -f $Package.name, $(Get-Date -f 'yyyyMMdd-HHmmss-ff'), $DocNum
            $ObjRequest.Request.InvoiceId = $InvoiceId
            $ObjRequest.Request.LocalDate = [string]$(Get-Date $ReceiptTimestamp -f 'yyy-MM-ddTHH:mm:ss')
            $ObjRequest.Request.CustomerReceipt.Items[0].Price = $Doc['Сумма']
            $ObjRequest.Request.CustomerReceipt.Items[0].Amount = $Doc['Сумма']

            # collect receipt
            $lstReceipts.Add($ObjRequest) > $null
            $ObjRequest = $null

        } # // for 

        " > receipts count: $($lstReceipts.count) prepared" | Write-Log

        # add ht with data into lst
        $packData.Add(@{
            filename = $SourceFile.Name
            filetype = $fileData.filetype
            receipts = $lstReceipts
        }) > $null

    } # // foreach

    $Package.Add('data', $packData)

    return $Package

} # //  Get-PackageData

function Get-StatisticalTable {

    # calculate metrics err, success, sum

    param(
        $rowsCollection
    )

    # rowsCollection is array of hashtables
    # @(
    #    @{key = value}
    #    @{key = value}
    # )

    # inc data should be collection, if not - create empty array lst
    if ($null -eq $rowsCollection) { [System.Collections.ArrayList]$rowsCollection = @() }
    if ($rowsCollection -is [hashtable]) { [System.Collections.ArrayList]$rowsCollection = @($rowsCollection) }


    $stat = @{
        scount = 0
        ecount = 0
        tcount = 0
        ssum = [double]0
        esum = [double]0
        tsum = [double]0
    }

    $duration = $null

    $rowsCollection | % {
        
        $stat.tcount++
        $stat.tsum += $_.sum
       
        if ($_.success -eq $true) { $stat.scount++ } else { $stat.ecount++ } 
        if ($_.success -eq $true) { $stat.ssum += $_.sum } else { $stat.esum += $_.sum }

        # if duration key exists then summarize
        if ($_.ContainsKey('duration')) {
            $duration += [timespan]::parse($_.duration)
        }

    }

    if ($null -ne $duration) { $stat.Add('duration', "{0:g}" -f $duration) }

    return $stat

} # // Get-StatisticalTable

function ConvertTo-FlatTable {

      # save transactions info into a userfriendly plain table
      # for best error analysing if happened

      param(
        [hashtable]$Package,  
        [string]$pathFile
    )

    # header
    $headFileRow = @('packagename', 'packagesuccess', 'filename', 'filesuccess', 'receiptpushdt', 'receiptorder', 'receiptsum', 'receiptsuccess', 'receiptinvoiceid', 'receiptidferma')
    $headFileRow -join ';' | Out-File -FilePath $pathFile -Encoding utf8 -Append -Force

    for ($fIndex=0; $fIndex -le $Package.data.count-1; $fIndex++) {

        # current file data
        $fileData = $Package.data[$fIndex]

        # iterate over transactions, strict order is needed
        for ($tIndex=0; $tIndex -le $fileData.transactions.count-1; $tIndex++) {

            $transData = $fileData.transactions[$tIndex]
            $orderRow = "{0};{1};{2};{3};{4};{5:d6};{6};{7};{8};{9}" -f $Package.name, $Package.success, $fileData.filename, $fileData.success, $transData.pushtimestamp, $($tIndex + 1), $transData.sum, $(if ($transData.success -eq $true) {1} else {0}), $transData.invoiceid, $transData.receiptid
            $orderRow | Out-File -FilePath $pathFile -Encoding utf8 -Append -Force

        } # // for

    } # // for

} # // OutTo-FlatTable 

function Get-Reports {

    # calc and save reports

    param(
        [hashtable]$Package
    )

    "calculate and saving reports..." | Write-Log  

    # if folder exists, simply existing item returns, example: _report\packagename\
    New-Item -Path $Package.report -ItemType Directory -ErrorAction SilentlyContinue > $null

    # package report file path
    $pathPackageReport = "{0}\{1}-total.csv" -f $Package.report, $Package.name

    # package report header
    $headPackRow = @('Файл','Отправлено чеков','Не отправлено чеков','Всего чеков','Отправлено сумма','Не отправлено сумма','Всего сумма')
    $headPackRow -join ';' | Out-File -FilePath $pathPackageReport -Encoding utf8 -Append -Force

    # iterate over files in package, strict order is needed
    for ($fIndex=0; $fIndex -le $Package.data.count-1; $fIndex++) {

        # current file data
        $fileData = $Package.data[$fIndex]
        # file report path
        $pathFileReport = "{0}\{1}@{2}-receipts.csv" -f $Package.report, $Package.name, $fileData.filename.Replace('.txt', '')

        # file report header
        $headFileRow = @('Дата время', 'Порядковый №', 'Сумма', 'Чек отправлен (1-да, 0-нет)', 'ID чека внутренний', 'ID чека внешний (ferma OFD)')
        $headFileRow -join ';' | Out-File -FilePath $pathFileReport -Encoding utf8 -Append -Force

        # iterate over transactions, strict order is needed
        for ($tIndex=0; $tIndex -le $fileData.transactions.count-1; $tIndex++) {
            $transData = $fileData.transactions[$tIndex]
            $orderRow = "{0};{1:d6};{2};{3};{4};{5}" -f $transData.pushtimestamp, $($tIndex + 1), $transData.sum, $(if ($transData.success -eq $true) {1} else {0}), $transData.invoiceid, $transData.receiptid
            $orderRow | Out-File -FilePath $pathFileReport -Encoding utf8 -Append -Force
        } # // for
        
        # file total row out
        $fileStat = Get-StatisticalTable -Rows $fileData.transactions
        $fTotalRow = @($fileData.filename, $fileStat.scount, $fileStat.ecount, $fileStat.tcount, $fileStat.ssum, $fileStat.esum, $fileStat.tsum)
        @(
            ''
            $headPackRow -join ';'
            $fTotalRow -join ';'
            ''
            "#@$($Package.mode) mode@#"
        ) | Out-File -FilePath $pathFileReport -Encoding utf8 -Append -Force

        # package row is equal file total row
        $fTotalRow -join ';' | Out-File -FilePath $pathPackageReport -Encoding utf8 -Append -Force

    } # // for

    # package total row out
    $packStat = Get-StatisticalTable -Rows $Package.data.transactions
    $pTotalRow = @('ИТОГ', $packStat.scount, $packStat.ecount, $packStat.tcount, $packStat.ssum, $packStat.esum, $packStat.tsum)
    @(
        $pTotalRow -join ';'
        ''
        "#@$($Package.mode) mode@#"
     ) | Out-File -FilePath $pathPackageReport -Encoding utf8 -Append -Force

} # // Get-Reports

function Compress-Package {

    # move package from the queue
    # compress package

    param(
        [hashtable]$Package
    )

    "compressing package..." | Write-Log

    if (!($PackageToZip = Move-Item -Path $Package.package -Destination $Package.zip -Force -PassThru -ErrorAction SilentlyContinue)) {
        "can not move package $($Package.name) from queue to zip folder", "package $($Package.name) stay stucked" | Write-Log -e
        return $false
    }
    "package moved from the queue folder" | Write-Log

    # example: zip\packagename.zip if success package or zip\packagename_error.zip if unsuccessful
    $pathPackageZipped = "{0}\{1}.zip" -f $Package.zip, $Package.name

    # if not success
    if ($Package.success -ne $true) {

        # errors, mark package name with _error suffix
        @(
            "package $($Package.name) contains error transactions"
            "package name will be marked with _error suffix"
            "to resolve issue human assistance needed"
            "package content should be analyzed, error receipts (unsuccessful transactions) need to push again"
        ) | Write-Log -e

        $pathPackageZipped = $pathPackageZipped.Replace('.zip', '_error.zip')

    } # // if

    Compress-Archive -Path $PackageToZip.FullName -DestinationPath $pathPackageZipped -CompressionLevel Optimal -Force

    # check archived package exists
    if (!($PackageZipped = Get-Item -Path $pathPackageZipped -ErrorAction SilentlyContinue)) {
        "can not compress package $($Package.name) into zip $pathPackageZipped " | Write-Log -e
        return $false
    }
    
    if (($lengthZip = $PackageZipped.Length ) -gt 0) {
        "package zipped $($lengthZip/1Kb) Kbite $pathPackageZipped" | Write-Log
        Remove-Item -Path $PackageToZip -Force -Recurse
    } else {
        "can not get zipped package size" | Write-Log -e
    } # // if..else

    #return $pathPackageZipped

} # // Compress-Package

