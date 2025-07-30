function Invoke-SecurityReview {
    #Define what we consider "modern" and "legacy" MFA methods
    $modernMethods = @("Passwordless", "MS Auth App", "FIDO2")
    $legacyMethods = @("TOTP/Software", "SMS/Voice", "Email")
    
    #These roles are flagged as privileged and will reduce the user’s score if used without proper MFA - add more if you want!
    $privRoles = @("Global Administrator", "Privileged Role Administrator", "Security Administrator", "Conditional Access Administrator")

    Write-Host "Fetching all member user accounts and their properties..."
    $allMembers = Get-MgBetaUser -All -Filter "userType eq 'Member'" -Property "displayName,userPrincipalName,accountEnabled,createdDateTime,passwordPolicies,signInActivity,lastPasswordChangeDateTime,userType,usageLocation"
    $users = $allMembers | Where-Object { $_.usageLocation -ne $null }


    # This block maps each user to any roles they're a member of
    Write-Host "Building a map of user roles..."
    $roleMap = @{}
    Get-MgBetaDirectoryRole | ForEach-Object {
        $role = $_
        Get-MgBetaDirectoryRoleMember -DirectoryRoleId $role.Id | ForEach-Object {
            if ($_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.user") {
                $memberUPN = $_.AdditionalProperties["userPrincipalName"]
                if ($memberUPN) {
                    if ($roleMap.ContainsKey($memberUPN)) {
                        $roleMap[$memberUPN] += $role.DisplayName
                    } else {
                        $roleMap[$memberUPN] = @($role.DisplayName)
                    }
                }
            }
        }
    }
    Write-Host "Role map created successfully."

    #Scoring function that deducts points based on risky user traits
    function Calculate-UserScore($mfaEnabled, $passwordNeverExpires, $neverSignedIn, $privilegedRole) {
        $score = 100
        if (-not $mfaEnabled) { $score -= 50 }
        if ($passwordNeverExpires) { $score -= 20 }
        if ($neverSignedIn) { $score -= 20 }
        if ($privilegedRole) { $score -= 10 }
        if ($score -lt 0) { $score = 0 }
        return $score
    }

    $reportMap = @{}
    Write-Host "Fetching consolidated MFA registration report via direct API call..."
    
    try {
        Write-Host "Requesting new access token for beta API call..."
        $tokenBody = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $AppId
            Client_Secret = $ClientSecret
        }
        $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $tokenBody -ErrorAction Stop
        $accessToken = $tokenResponse.access_token

        $headers = @{ 'Authorization' = "Bearer $accessToken" }
        $allReportDetails = [System.Collections.Generic.List[object]]::new()
        $uri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails"

        #Handle paging in Graph API results
        while ($uri) {
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop
            if ($response.value) { $allReportDetails.AddRange($response.value) }
            $uri = $response.'@odata.nextLink'
        }

        #Store the registration details per user, indexed by UPN
        if ($allReportDetails.Count -gt 0) {
            $groupedReport = $allReportDetails | Group-Object -Property UserPrincipalName
            foreach ($group in $groupedReport) {
                $reportMap[$group.Name] = $group.Group[0]
            }
            Write-Host "MFA registration report fetched successfully."
        } else {
            Write-Warning "MFA registration report returned no data."
        }
    } catch {
        Write-Warning "Failed to fetch MFA report via API. Error: $($_.Exception.Message)"
    }

    Write-Host "Processing each user..."
    $data = @()
    foreach ($user in $users) {
        $risk = @()
        $mfaMethodsFound = [System.Collections.Generic.HashSet[string]]::new()
        
        try {
            #Query Graph for all registered auth methods for this user - this must use the Beta Graph otherwise it will break the search (as of July 2025)
            $authMethods = Get-MgBetaUserAuthenticationMethod -UserId $user.Id -All -ErrorAction SilentlyContinue
            foreach ($method in $authMethods) {
                switch ($method.'@odata.type') {
                    "#microsoft.graph.phoneAuthenticationMethod" { [void]$mfaMethodsFound.Add("SMS/Voice") }
                    "#microsoft.graph.passwordlessMicrosoftAuthenticatorAuthenticationMethod" { [void]$mfaMethodsFound.Add("Passwordless") }
                    "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" { [void]$mfaMethodsFound.Add("MS Auth App") }
                    "#microsoft.graph.fido2AuthenticationMethod" { [void]$mfaMethodsFound.Add("FIDO2") }
                    "#microsoft.graph.softwareOathAuthenticationMethod" { [void]$mfaMethodsFound.Add("TOTP/Software") }
                    "#microsoft.graph.emailAuthenticationMethod" { [void]$mfaMethodsFound.Add("Email") }
                }
            }
        } catch { 
            #Could be permissions issue or user without methods
            $risk += "MFA Check Failed" 
        }

        #Supplement with data from the raw API report if available
        if ($reportMap.ContainsKey($user.UserPrincipalName)) {
            $userReport = $reportMap[$user.UserPrincipalName]
            if ($userReport -is [array]) { $userReport = $userReport[0] }

            if ($userReport.IsMfaRegistered) {
                foreach ($authMethod in $userReport.authMethods) {
                    switch ($authMethod) {
                        "appNotification" { [void]$mfaMethodsFound.Add("MS Auth App") }
                        "appCode"         { [void]$mfaMethodsFound.Add("MS Auth App") }
                        "mobilePhone"     { [void]$mfaMethodsFound.Add("SMS/Voice") }
                        "alternateMobilePhone" { [void]$mfaMethodsFound.Add("SMS/Voice") }
                        "officePhone"     { [void]$mfaMethodsFound.Add("SMS/Voice") }
                        "email"           { [void]$mfaMethodsFound.Add("Email") }
                    }
                }
            }
        }

        #Determine MFA status
        $mfaStatus = "Not Enabled"
        if ($mfaMethodsFound.Count -gt 0) {
            $isModern = $false; $isLegacy = $false
            foreach ($methodName in $mfaMethodsFound) {
                if ($modernMethods -contains $methodName) { $isModern = $true }
                if ($legacyMethods -contains $methodName) { $isLegacy = $true }
            }
            if ($isModern) { $mfaStatus = "Modern MFA" } 
            elseif ($isLegacy) { $mfaStatus = "Legacy MFA" }
        }

        $mfaEnabled = ($mfaStatus -ne "Not Enabled")
        if (-not $mfaEnabled) { $risk += "MFA Not Registered" }

        #Check if the user’s password never expires
        $passwordNeverExpires = $user.passwordPolicies -like "*DisablePasswordExpiration*"
        if ($passwordNeverExpires) { $risk += "Password Never Expires" }

        #Handle sign-in activity (some users might never have signed in)
        $lastSignIn = "N/A"; $neverSignedIn = $false
        if ($null -eq $user.signInActivity.lastSignInDateTime) {
            $neverSignedIn = $true; $risk += "Never Signed In"; $lastSignIn = "Never"
        } else {
            $lastSignIn = Get-Date $user.signInActivity.lastSignInDateTime
        }

        #Capture timestamps and fallbacks
        $createdDate = if ($user.createdDateTime) { Get-Date $user.createdDateTime } else { 'N/A' }
        $lastPassChange = if ($user.lastPasswordChangeDateTime) { Get-Date $user.lastPasswordChangeDateTime } else { 'N/A' }

        #Check if user has any privileged roles assigned
        $role = "None"; $privilegedRole = $false
        if ($roleMap.ContainsKey($user.userPrincipalName)) {
            $userRoles = $roleMap[$user.userPrincipalName]
            $role = $userRoles -join ", "
            foreach ($r in $userRoles) {
                if ($privRoles -contains $r) {
                    $privilegedRole = $true
                    break
                }
            }
        }

        #Final risk score tally
        $score = Calculate-UserScore -mfaEnabled $mfaEnabled -passwordNeverExpires $passwordNeverExpires -neverSignedIn $neverSignedIn -privilegedRole $privilegedRole
        
        #Add user summary to report dataset
        $data += [PSCustomObject]@{
            Name           = $user.displayName
            UPN            = $user.userPrincipalName
            Enabled        = $user.accountEnabled
            Created        = $createdDate
            LastSignIn     = $lastSignIn
            MFAStatus      = $mfaStatus
            MFAMethods     = ($mfaMethodsFound | Sort-Object -Unique) -join ", "
            Role           = $role
            LastPassChange = $lastPassChange
            Flags          = ($risk -join ", ")
            Score          = $score
        }
    }

    return $data
}
