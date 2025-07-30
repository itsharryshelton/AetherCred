function Invoke-GuestUserReview {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    Write-Host "Initiating Guest User Review..." -ForegroundColor Cyan

    try {
        Write-Host "Requesting new access token for Guest User API calls..." -ForegroundColor Yellow
        $tokenBody = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $AppId
            Client_Secret = $ClientSecret
        }
        $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token" -Method POST -Body $tokenBody -ErrorAction Stop
        $accessToken = $tokenResponse.access_token

        if ([string]::IsNullOrWhiteSpace($accessToken)) {
            throw "Failed to acquire a valid access token."
        }
        Write-Host "Access token acquired successfully." -ForegroundColor Green

        $headers = @{ 'Authorization' = "Bearer $accessToken" }

        Write-Host "Fetching all guest user accounts..."
        $allGuestUsers = [System.Collections.Generic.List[object]]::new()
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=displayName,mail,userPrincipalName,createdDateTime,signInActivity"
        
        while ($uri) {
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop
            if ($response.value) { $allGuestUsers.AddRange($response.value) }
            $uri = $response.'@odata.nextLink'
        }
        Write-Host "Found $($allGuestUsers.Count) guest user accounts."

        Write-Host "Fetching consolidated MFA registration report..."
        $mfaReportMap = @{}
        try {
            $mfaUri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails"
            $allMfaDetails = [System.Collections.Generic.List[object]]::new()
            
            while ($mfaUri) {
                $mfaResponse = Invoke-RestMethod -Uri $mfaUri -Headers $headers -Method GET -ErrorAction Stop
                if ($mfaResponse.value) { $allMfaDetails.AddRange($mfaResponse.value) }
                $mfaUri = $mfaResponse.'@odata.nextLink'
            }

            foreach ($detail in $allMfaDetails) {
                $mfaReportMap[$detail.userPrincipalName] = $detail
            }
            Write-Host "MFA registration report fetched successfully."
        } catch {
            Write-Warning "Could not retrieve MFA registration report. MFA status for guests will be marked as 'Unknown'. Error: $($_.Exception.Message)"
        }

        Write-Host "Processing guest user data..."
        $reportData = foreach ($guest in $allGuestUsers) {
            $mfaStatus = "Unknown"
            if ($mfaReportMap.ContainsKey($guest.userPrincipalName)) {
                $mfaInfo = $mfaReportMap[$guest.userPrincipalName]
                $mfaStatus = if ($mfaInfo.isMfaRegistered) { "Registered" } else { "Not Registered" }
            }

            $lastSignIn = "Never"
            if ($null -ne $guest.signInActivity.lastSignInDateTime) {
                $lastSignIn = Get-Date $guest.signInActivity.lastSignInDateTime
            }
            
            $emailAddress = if (-not [string]::IsNullOrWhiteSpace($guest.mail)) { $guest.mail } else { $guest.userPrincipalName }

            [PSCustomObject]@{
                DisplayName    = $guest.displayName
                Email          = $emailAddress
                MFAStatus      = $mfaStatus
                LastSignInDate = $lastSignIn
                CreatedDate    = Get-Date $guest.createdDateTime
            }
        }
        
        Write-Host "Guest User Review completed successfully." -ForegroundColor Green
        return $reportData
    }
    catch {
        Write-Error "Failed to execute Guest User Review. Error: $($_.Exception.Message)"
        return $null
    }
}
