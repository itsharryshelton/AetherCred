<#

Written by Harry Shelton - July 2025
Script Name: AetherCred

Script requires the Microsoft Graph PowerShell SDK.
Required permissions are consolidated for app creation and reporting.

#>

# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================
$AppName = "AetherCred"
$LogoFileName = "AetherCredLogoCloudEntraSize.png"
$HomePageURL = "https://github.com/itsharryshelton"


# STEP 1: CONNECT TO MICROSOFT GRAPH
# ==============================================================================
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes @(
    "User.Read.All",
    "Directory.Read.All",
    "UserAuthenticationMethod.Read.All",
    "AuditLog.Read.All",
    "Reports.Read.All",
    "Application.ReadWrite.All"
)


# STEP 2: ENTERPRISE APPLIATION CREATION / CHECKS
# ==============================================================================
Write-Host "Checking for '$AppName' Enterprise Application..."
try {
    #Check if the application already exists by its display name
    $existingApp = Get-MgApplication -Filter "displayName eq '$AppName'"
    
    if ($null -eq $existingApp) {
        Write-Host "'$AppName' application not found. Creating it now..." -ForegroundColor Yellow

        #Step 2a: Create the Application Registration with Homepage URL
        Write-Host "Creating new Application Registration named '$AppName'..."
        $appParams = @{
            DisplayName = $AppName
            Web = @{
                HomePageUrl = $HomePageURL
            }
        }
        $app = New-MgApplication -BodyParameter $appParams
        Write-Host "Successfully created Application Registration (App ID: $($app.AppId)) with homepage." -ForegroundColor Green

        #Step 2b: Create the Service Principal (Enterprise Application)
        Write-Host "Creating Service Principal..."
        $sp = New-MgServicePrincipal -AppId $app.AppId
        Write-Host "Successfully created Service Principal." -ForegroundColor Green

        # Step 2c: Upload the logo
        $scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
        $logoPath = Join-Path $scriptFolder $LogoFileName
        
        if (Test-Path -Path $logoPath -PathType Leaf) {
            Write-Host "Uploading logo from '$logoPath'..."
            Set-MgApplicationLogo -ApplicationId $app.Id -InFile $logoPath
            Write-Host "Successfully uploaded custom logo." -ForegroundColor Green
        }
        else {
            Write-Warning "Logo file '$LogoFileName' not found in the script folder. Skipping logo upload."
        }
    } else {
        Write-Host "'$AppName' application already exists. Verifying configuration..." -ForegroundColor Green
        if ($existingApp.Web.HomePageUrl -ne $HomePageURL) {
            Write-Host "Homepage URL is incorrect. Updating..." -ForegroundColor Yellow
            Update-MgApplication -ApplicationId $existingApp.Id -Web @{ HomePageUrl = $HomePageURL }
            Write-Host "Homepage URL successfully updated." -ForegroundColor Green
        } else {
            Write-Host "Homepage URL is already correctly configured."
        }
    }
}
catch {
    Write-Error "An error occurred during application setup. Please check permissions. Error: $_"
    #Exit the script if app setup fails, as it's a core part
    return
}



# STEP 3: DEFINE CATEGORIES AND GATHER INITIAL DATA
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


# STEP 4: HELPER FUNCTION FOR SCORING
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


# STEP 5: GATHER MFA REPORTS & PROCESS EACH USER
# ==============================================================================
# --- HYBRID MFA DATA GATHERING (via Direct API Call) ---
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
    
    # 1. Primary Check: Use the Get-MgUserAuthenticationMethod command
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

    # 2. Fallback Check: Use the data from our direct API call
    if ($reportMap.ContainsKey($user.UserPrincipalName)) {
        $userReport = $reportMap[$user.UserPrincipalName]
        if ($userReport -is [array]){ $userReport = $userReport[0] }

        if ($userReport.IsMfaRegistered) {
            foreach ($authMethod in $userReport.authMethods) {
                switch ($authMethod) {
                    "appNotification"      { [void]$mfaMethodsFound.Add("MS Auth App") }
                    "appCode"              { [void]$mfaMethodsFound.Add("MS Auth App") }
                    "mobilePhone"          { [void]$mfaMethodsFound.Add("SMS/Voice") }
                    "alternateMobilePhone" { [void]$mfaMethodsFound.Add("SMS/Voice") }
                    "officePhone"          { [void]$mfaMethodsFound.Add("SMS/Voice") }
                    "email"                { [void]$mfaMethodsFound.Add("Email") }
                }
            }
        }
    }

    # 3. Categorize based on the combined results
    $mfaStatus = "Not Enabled"
    if ($mfaMethodsFound.Count -gt 0) {
        $isModern = $false; $isLegacy = $false
        foreach ($methodName in $mfaMethodsFound) {
            if ($modernMethods -contains $methodName) { $isModern = $true }
            if ($legacyMethods -contains $methodName) { $isLegacy = $true }
        }
        if ($isModern) { 
            $mfaStatus = "Modern MFA" 
        } elseif ($isLegacy) { 
            $mfaStatus = "Legacy MFA" 
        }
    }
    
    $mfaEnabled = ($mfaStatus -ne "Not Enabled")
    if (-not $mfaEnabled) { 
        $risk += "MFA Not Registered" 
    }

    # --- OTHER CHECKS ---
    $passwordNeverExpires = $false
    if ($user.passwordPolicies -like "*DisablePasswordExpiration*") { 
        $passwordNeverExpires = $true 
    } else { 
        $risk += "Password Expiry Enabled" 
    }

    # --- LastSignIn Date Format ---
    $lastSignIn = "N/A"; $neverSignedIn = $false
    try {
        $lastSignInRaw = $user.signInActivity.lastSignInDateTime
        if ($null -eq $lastSignInRaw) {
            $neverSignedIn = $true; $risk += "Never Signed In"; $lastSignIn = "Never"
        } else {
            if ($lastSignInRaw -is [string] -and $lastSignInRaw -match '/Date\((\d+)\)/') {
                $timestampMs = $matches[1]
                $epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
                $lastSignIn = $epoch.AddMilliseconds($timestampMs).ToLocalTime()
            } else {
                $lastSignIn = Get-Date $lastSignInRaw
            }
        }
    } catch { 
        $risk += "SignIn Policy Error" 
    }

    # --- CreatedDateTime Date Format ---
    $createdDate = "N/A"
    try {
        $createdDateRaw = $user.createdDateTime
        if ($null -ne $createdDateRaw) {
            if ($createdDateRaw -is [string] -and $createdDateRaw -match '/Date\((\d+)\)/') {
                $timestampMs = $matches[1]
                $epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
                $createdDate = $epoch.AddMilliseconds($timestampMs).ToLocalTime()
            } else {
                $createdDate = Get-Date $createdDateRaw
            }
        }
    } catch { # If there's an error, the value will remain "N/A"
    }

    # --- lastPasswordChangeDateTime Date Format ---
    $lastPassChange = "N/A"
    try {
        $lastPassChangeRaw = $user.lastPasswordChangeDateTime
        if ($null -ne $lastPassChangeRaw) {
            if ($lastPassChangeRaw -is [string] -and $lastPassChangeRaw -match '/Date\((\d+)\)/') {
                $timestampMs = $matches[1]
                $epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
                $lastPassChange = $epoch.AddMilliseconds($timestampMs).ToLocalTime()
            } else {
                $lastPassChange = Get-Date $lastPassChangeRaw
            }
        }
    } catch { # If there's an error, the value will remain "N/A"
    }

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

    # --- SCORE & DATA COLLECTION ---
    $score = Calculate-UserScore -mfaEnabled $mfaEnabled -passwordNeverExpires $passwordNeverExpires -neverSignedIn $neverSignedIn -privilegedRole $privilegedRole
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


# STEP 6: EXPORT AND LAUNCH
# ==============================================================================
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- EXPORT JSON as JS ---
$jsVariableName = "aetherCredData"
$lastUpdatedJs = "var lastUpdated = '$(Get-Date)';"
$jsContent = $lastUpdatedJs + "var $jsVariableName = " + ($data | ConvertTo-Json -Depth 5 -Compress) + ";"
$jsFilePath = Join-Path $scriptFolder "AetherCred-Data.js"
$jsContent | Out-File -Encoding UTF8 -FilePath $jsFilePath
Write-Host "JS data exported to $jsFilePath"

# --- EXPORT to CSV ---
$csvFilePath = Join-Path $scriptFolder "AetherCred-Data.csv"
$data | Export-Csv -Path $csvFilePath -NoTypeInformation
Write-Host "CSV data exported to $csvFilePath"

# --- LAUNCH REPORT ---
$reportHtmlPath = Join-Path $scriptFolder "AetherCred-Dashboard.html"
if (Test-Path $reportHtmlPath) {
    Write-Host "Launching dashboard..."
    Start-Process $reportHtmlPath
} else {
    Write-Warning "Could not find AetherCred-Dashboard.html in the script folder."
}

#Disconnect when script is finished
Disconnect-MgGraph
