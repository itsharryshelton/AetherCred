function Invoke-SecurityReview {
    # ==============================================================================
    # DEFINE CATEGORIES AND GATHER INITIAL DATA
    # ==============================================================================
    $modernMethods = @("Passwordless", "MS Auth App", "FIDO2")
    $legacyMethods = @("TOTP/Software", "SMS/Voice", "Email")
    $privRoles = @("Global Administrator", "Privileged Role Administrator", "Security Administrator", "Conditional Access Administrator")

    Write-Host "Fetching all user accounts and their properties..."
    $users = Get-MgUser -All -Property "displayName,userPrincipalName,accountEnabled,createdDateTime,passwordPolicies,signInActivity,lastPasswordChangeDateTime"

    Write-Host "Building a map of user roles..."
    $roleMap = @{}
    Get-MgDirectoryRole | ForEach-Object {
        $role = $_
        Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id | ForEach-Object {
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

    # ==============================================================================
    # HELPER FUNCTION FOR SCORING
    # ==============================================================================
    function Calculate-UserScore($mfaEnabled, $passwordNeverExpires, $neverSignedIn, $privilegedRole) {
        $score = 100
        if (-not $mfaEnabled) { $score -= 50 }
        if (-not $passwordNeverExpires) { $score -= 20 }
        if ($neverSignedIn) { $score -= 20 }
        if ($privilegedRole) { $score -= 10 }
        if ($score -lt 0) { $score = 0 }
        return $score
    }

    # ==============================================================================
    # GATHER MFA REPORTS & PROCESS EACH USER
    # ==============================================================================
    $reportMap = @{}
    Write-Host "Fetching consolidated MFA registration report via direct API call..."
    try {
        $allReportDetails = [System.Collections.Generic.List[object]]::new()
        $uri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails"
        while ($uri) {
            $response = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
            if ($response.value) { $allReportDetails.AddRange($response.value) }
            $uri = $response.'@odata.nextLink'
        }

        if ($allReportDetails.Count -gt 0) {
            $groupedReport = $allReportDetails | Group-Object -Property UserPrincipalName
            foreach ($group in $groupedReport) {
                $reportMap[$group.Name] = $group.Group[0]
            }
            Write-Host "Consolidated report fetched and de-duplicated successfully."
        } else {
            Write-Warning "Consolidated MFA report returned no data. This can be due to licensing (Entra ID P1 is required)."
        }
    } catch {
        Write-Warning "Failed to fetch MFA report via API. Error: $($_.Exception.Message). Legacy MFA status will be incomplete."
    }

    # --- PROCESS USER DATA ---
    Write-Host "Processing each user..."
    $data = @()
    foreach ($user in $users) {
        $risk = @()
        $mfaMethodsFound = [System.Collections.Generic.HashSet[string]]::new()
        
        try {
            $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction SilentlyContinue
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
            $risk += "MFA Check Failed" 
        }

        if ($reportMap.ContainsKey($user.UserPrincipalName)) {
            $userReport = $reportMap[$user.UserPrincipalName]
            if ($userReport -is [array]){ $userReport = $userReport[0] }

            if ($userReport.IsMfaRegistered) {
                foreach ($authMethod in $userReport.authMethods) {
                    if (($authMethod -eq "appNotification") -or ($authMethod -eq "appCode")) {
                        [void]$mfaMethodsFound.Add("MS Auth App")
                    }
                    elseif (($authMethod -eq "mobilePhone") -or ($authMethod -eq "alternateMobilePhone") -or ($authMethod -eq "officePhone")) {
                        [void]$mfaMethodsFound.Add("SMS/Voice")
                    }
                    elseif ($authMethod -eq "email") {
                        [void]$mfaMethodsFound.Add("Email")
                    }
                }
            }
        }

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
        
        $passwordNeverExpires = $user.passwordPolicies -like "*DisablePasswordExpiration*"
        if (-not $passwordNeverExpires) { $risk += "Password Expiry Enabled" }

        $lastSignIn = "N/A"; $neverSignedIn = $false
        if ($null -eq $user.signInActivity.lastSignInDateTime) {
            $neverSignedIn = $true; $risk += "Never Signed In"; $lastSignIn = "Never"
        } else { $lastSignIn = Get-Date $user.signInActivity.lastSignInDateTime }

        $createdDate = if ($user.createdDateTime) { (Get-Date $user.createdDateTime) } else { 'N/A' }
        $lastPassChange = if ($user.lastPasswordChangeDateTime) { (Get-Date $user.lastPasswordChangeDateTime) } else { 'N/A' }
        
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

        $score = Calculate-UserScore -mfaEnabled $mfaEnabled -passwordNeverExpires $passwordNeverExpires -neverSignedIn $neverSignedIn -privilegedRole $privilegedRole
        $data += [PSCustomObject]@{
            Name           = $user.displayName; UPN = $user.userPrincipalName; Enabled = $user.accountEnabled
            Created        = $createdDate; LastSignIn = $lastSignIn; MFAStatus = $mfaStatus
            MFAMethods     = ($mfaMethodsFound | Sort-Object -Unique) -join ", "
            Role           = $role; LastPassChange = $lastPassChange
            Flags          = ($risk -join ", "); Score = $score
        }
    }
    
    return $data
}