$global:DEBUG=$true

$global:APIURL="https://app.mango-office.ru/vpbx/"
$global:APIKEY=""
$global:APISALT=""

Function Compute-Sha-256-Hash {
Param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ClearString
)

    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256')
    $hash = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ClearString))

    $hashString = [System.BitConverter]::ToString($hash)
    $hashString.Replace('-', '').ToLower()
}

Function SignBody {
Param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$APIKEY,

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$APISALT,

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$body
)
    $hash = Compute-Sha-256-Hash -ClearString "$($APIKEY)$($body)$($APISALT)"
    return $hash
}

Function New-Callback{
Param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$clbk_extension = $(throw "-clbk_extension is required."),

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$clbk_to_number = $(throw "-clbk_to_number is required."),

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$clbk_line_number = $(throw "-clbk_line_number is required."),

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$APIKEY = $(throw "-APIKEY is required."),

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$APISALT = $(throw "-APISALT is required."),

    [Parameter(Mandatory=$false, ValueFromPipeline=$false)]
    [string]$command_id
)
    if (-not $command_id -or $command_id.Length -lt 1) {
        $command_id = New-Guid
        Write-Debug "commaind_id = $command_id"
    }

    $body = @{
        command_id = $command_id
        from = @{
            extension = $clbk_extension
        }
        to_number = $clbk_to_number
        line_number = $clbk_line_number
        spi_headers = @{
            "Call-Info/answer-after" = 0
        }
    }
    $bodyJson = (ConvertTo-Json $body)

    try {
        $bodyHash = SignBody -APIKEY $APIKEY -APISALT $APISALT -body $bodyJson
    } catch {
        throw "Signing error"
    }

    $postData = @{
        vpbx_api_key = $APIKEY
        sign = $bodyHash
        json = $bodyJson
    }
    return $postData
}

Function New-MangoRequest {
Param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$Command = $(throw "-Command is required."),

    [Parameter(Mandatory=$true, ValueFromPipeline=$false)]
    [ValidateNotNullOrEmpty()]
    [hashtable]$Body = $(throw "-Body is required.")
)
    if (-not $global:Commands.ContainsKey($Command)) {
        Write-Warning "No such command `"$Command`""
        Write-Host -ForegroundColor Yellow "Available commands:"
        $global:Commands.GetEnumerator()  | % { Write-Host -ForegroundColor Yellow "$($_.Name)" }
        return
    }
    $Uri = "$global:APIURL$($global:Commands[$Command])"
    $ContentType = "application/x-www-form-urlencoded"

    if ($global:DEBUG) {
        # DEBUG OUTPUT
        Write-Host -ForegroundColor Cyan "Requested URL: $Uri"
        Write-Host -ForegroundColor Cyan "PostData:"
        if ($Body) {
            $Body.GetEnumerator()  | % { Write-Host -ForegroundColor Gray "$($_.Name)=$($_.Value)" }
        }
    }

    try {
        $result = Invoke-RestMethod -Method Post -Uri $Uri -Body $Body -ContentType $ContentType
    } catch {
        Write-Host -ForegroundColor Red "Error invoking API request"
        Write-Host -ForegroundColor Magenta "StatusCode:" $_.Exception.Response.StatusCode.value__ 
        Write-Host -ForegroundColor Magenta "StatusDescription:" $_.Exception.Response.StatusDescription
        throw
    }
    return $result
}


# VARS
# Commands array
$global:Commands = @{
    callback         = "commands/callback"
    callback_group   = "commands/callback_group"
    call_hangup      = "commands/call/hangup"
    sms              = "commands/sms"
}

# Results array
$global:Results = @{
    callback         = "result/callback"
    callback_group   = "result/callback_group"
    call_hangup      = "result/call/hangup"
    sms              = "result/sms"
}

$clbk_extension = "777"
$clbk_to_number = "74951111111"
$clbk_line_number = "74951111111"

# Get callback data
$callbackData = New-Callback -clbk_extension $clbk_extension `
                             -clbk_to_number $clbk_to_number `
                             -clbk_line_number $clbk_line_number `
                             -APIKEY $global:APIKEY -APISALT $global:APISALT

# Make a request
New-MangoRequest -Command "callback" -Body $callbackData
