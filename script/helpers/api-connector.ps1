function New-AuthToken {

    # get or new auth token

    param (
        [string]$Uri,
        [string]$Method = 'Post',
        [string]$Login,
        [string]$Password,
        [string]$pathAuthTokenJson
    )

    $JSON = @{Login = $Login; Password = $Password} | ConvertTo-Json -Depth 2 -Compress
    $Headers = @{
        'Content-Length' = $JSON.Length
        'Content-Value' = 'application/json; charset=utf-8'
    }
    $paramsInvoke = @{
        Uri = $Uri
        Method = $Method
        Body = $JSON
        Headers = $Headers
        ContentType = 'application/json; charset=utf-8'
    }

    try {
        $Response = Invoke-RestMethod @paramsInvoke -ErrorAction SilentlyContinue
        if ($pathAuthTokenJson) { $Response | ConvertTo-JSON -Depth 4 -Compress | Set-Content -Path $pathAuthTokenJson -Encoding UTF8 }
    }
    catch {
        $Response = $_.ErrorDetails.Message
        if ($pathAuthTokenJson) { $Response | Out-File $pathAuthTokenJson -Encoding UTF8 }
    }

    if ($Response.Status -eq 'Success') { return $Response.Data.AuthToken }
    else { return $false }

} # // New-AuthToken

function Push-Receipt {

    # push receipt using ferma api

    param (
        [pscustomobject]$Body,
        [string]$AuthToken,
        [string]$Uri,
        [string]$Method = 'Post'
    )

    $paramsInvoke = @{
        Uri = $Uri + "?AuthToken=" + $AuthToken
        Method = $Method
        Body = $Body | ConvertTo-Json -Depth 10 -Compress
        Headers = @{'Content-Value' = 'application/json; charset=utf-8'}
        ContentType = 'application/json; charset=utf-8'
    }

    try {
        $Response = Invoke-RestMethod @paramsInvoke -ErrorAction SilentlyContinue
    }
    catch {
        $Response = ConvertFrom-JSON -InputObject $_.ErrorDetails.Message
    }

    # result is pscustomobject
    return $Response

} # // Push-Receipt

function Push-PackageData {

    # push all receipts in package
    # result in .transactions property

    param (
        [hashtable]$Package,
        [string]$AuthToken,
        [hashtable]$paramsPush,
        [hashtable]$paramsAuth
    )

    "pushing all receipts..." | Write-Log

    # package will be marked as $true if all receipts transactions per package are successfull
    $Package.Add('success', $false)

    # package transactions
    [System.Collections.ArrayList]$lstPackageTransactions = @()
    # package errors counter
    [int]$errPackage = 0

    <#
        # packData is array of hashtables
        @(
            # fileData 1
            @{
                duration=
                filetype=
                receipts=@()
                filename=
                transactions=@()  
                ..
            }
            # fileData 2
            @{}
            ..
        )
    #>
    $packData = $Package.data

    for ($fIndex = 0; $fIndex -le $packData.count - 1; $fIndex++) {

        # current file data
        $fileData = $packData[$fIndex]
        " > file: $($fileData.filename)" | Write-log

         # file will be marked as $true if all receipts transactions per file are successfull
        $fileData.success = $false

        <#
            # lstFileTransactions is array of hashtables
            @(
                # htTransaction 1
                @{
                    sum=
                    success=
                    request=
                    response=
                    ..
                }
                # htTransaction 2
                @{}
                ..
            )
        #>

        # file transactions
        [System.Collections.ArrayList]$lstFileTransactions = @()
        # file errors counter
        [int]$errFile = 0
        # start file process timestmamp
        $tsFilePush = Get-Date

        $Receipts = $fileData.receipts
        " > pushing count: $($Receipts.count) receipts..." | Write-log

        # push receipts one by one in strict order
        for ($rIndex = 0; $rIndex -le $Receipts.count - 1; $rIndex++) {

            $rNum = $rIndex + 1
            
            Write-Progress -Activity "Pushing..." -Status "$rNum/$($Receipts.count) complete:" -PercentComplete $($rNum*100/$Receipts.count)

            # current receipt request
            $objRequest = $Receipts[$rIndex]
            $tsReceiptPush = Get-Date -f 'dd.MM.yyyy HH:mm:ss'
           
            # real push
            [pscustomobject]$ObjResponse = Push-Receipt -Body $objRequest -AuthToken $AuthToken @paramsPush
            
            # if server returns an error: auth token expired
            if (($ObjResponse.Status -eq 'Failed') -and ($ObjResponse.Error.Code -eq '1001')) {

                # get new auth token
                if ($AuthToken = New-AuthToken @paramsAuth) {
                    " > token expired. new token: $AuthToken" | Write-log
                    # push same receipt again
                    [pscustomobject]$ObjResponse = Push-Receipt -Body $objRequest -AuthToken $AuthToken @paramsPush
                } else {
                    " > token expired. can not get auth token" | Write-Log -e
                } # // if

            } # // if

            # debug push with error (empty) response
            #[pscustomobject]$ObjResponse = @{}

            # ht contains receipt transaction info
            $htTransaction = @{
                pushtimestamp = $tsReceiptPush # push transaction datetime (it is not receipt creation moment)
                invoiceid = $objRequest.Request.InvoiceId # internal receipt id (link to RCTransaction row for join)
                sum = [double]$objRequest.Request.CustomerReceipt.Items[0].Amount # receipt sum
                receiptid = $ObjResponse.Data.ReceiptId # response receipt id if sucess
                success = if ($ObjResponse.Data.ReceiptId) { $true } else { $false } # success
                packagename = $Package.name # package name
                sourcefilename = $fileData.filename # source file name
                request = $objRequest
                response = $ObjResponse
            }

            # if no success response
            if (!($ObjResponse.Data.ReceiptId)) { $errFile++ }
            
            # add transaction into collection
            $lstFileTransactions.Add($htTransaction) > $null

        } # // for ($rIndex = 0; $rIndex -le $Receipts.count - 1; $rIndex++)
       
        # calc file process duration
        $durationFile = New-TimeSpan -Start $tsFilePush
        $fileData.Add('duration', $("{0:g}" -f $durationFile))
        # calc package process duration
        $durationPackage += $durationFile
        # add file transactions into a file data
        $fileData.Add('transactions', $lstFileTransactions)
        # mark file as successful if no errors happened
        if ($errFile -eq 0) { $fileData.success = $true }
        # add errors into package errors
        $errPackage += $errFile
        # add file transactions into package transactions
        $lstPackageTransactions += $lstFileTransactions
        # file metrics 
        $fileStat = Get-StatisticalTable -rowsCollection $lstFileTransactions

        # log file statistics
        @(
            " > receipts pushed success/error/total: {0}/{1}/{2}" -f $fileStat.scount, $fileStat.ecount, $fileStat.tcount
            " > sum success/error/total: {0}/{1}/{2}" -f $fileStat.ssum, $fileStat.esum, $fileStat.tsum
            " > duration: {0}" -f $fileData.duration
            " > {0}" -f $(if ($errFile -eq 0) { '!SUCCESS' } else {'!ERROR'})
        ) | Write-Log

    } # // for ($fIndex = 0; $fIndex -le $packData.count - 1; $fIndex++)

    # mark package as successful if no errors happened
    if ($errPackage -eq 0) { $Package.success = $true }
    # package duration
    $Package.Add('duration', $("{0:g}" -f $durationPackage))
    # package metrics
    $packStat = Get-StatisticalTable -rowsCollection $lstPackageTransactions

    # log package statistics
    @(
        "^"*50
        "total statistics for package: $($Package.name)"
        "receipts pushed success/error/total: {0}/{1}/{2}" -f $packStat.scount, $packStat.ecount, $packStat.tcount
        "sum pushed success/error/total: {0}/{1}/{2}" -f $packStat.ssum, $packStat.esum, $packStat.tsum
        "duration: {0:g}" -f $Package.duration
        "{0}" -f $(if ($errPackage -eq 0) { '!SUCCESS TOTAL :)' } else {'!ERROR TOTAL'})
        "^"*50
    ) | Write-Log

    return $Package

} # // Push-PackageData

function Get-ReceiptsRegistry {

    # get receipts registry from server

    param(
        [string]$idReceipt,
        $dtFrom,
        $dtTo
    )

    
} # // Get-ReceiptsRegistry