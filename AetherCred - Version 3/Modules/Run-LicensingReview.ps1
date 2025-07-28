function Invoke-LicensingReview {
    Write-Host "Fetching product SKUs and user license states..."
    try {
        # Create a mapping of SKU GUIDs to SkuPartNumber for initial lookup
        $skuIdToPartNumberMap = @{}
        $skuDisplayNameMap = @{} # New map for display names of top-level SKUs

        Get-MgSubscribedSku -All | ForEach-Object {
            $skuIdToPartNumberMap[$_.SkuId] = $_.SkuPartNumber
            # Populate SKU display name map for top-level SKUs
            $skuDisplayNameMap[$_.SkuPartNumber] = $_.AppliesTo + " - " + $_.SkuPartNumber # Example: "User - O365_BUSINESS_PREMIUM"
            # Attempt to use a more user-friendly name if available directly from Get-MgSubscribedSku
            if (-not [string]::IsNullOrEmpty($_.CapabilityStatus)) { # CapabilityStatus usually implies a main SKU
                 $skuDisplayNameMap[$_.SkuPartNumber] = $_.SkuPartNumber.Replace('_', ' ').Replace('O365', 'Microsoft 365').Replace('SPE', 'Microsoft 365').Replace('EMS', 'Enterprise Mobility + Security').Trim()
            }
        }

        # --- Translation table for user-friendly license names (for specific overrides or common components) ---
        $friendlyNameMap = @{
            "SPB"                        = "Microsoft 365 Business Premium" 
            "O365_BUSINESS_PREMIUM"      = "Microsoft 365 Business Premium"
            "MICROSOFT_365_BUSINESS_STANDARD_NO_TEAMS" = "Microsoft 365 Business Standard (no Teams)"
            "Microsoft_365_Business_Standard_EEA_(no_Teams)" = "Microsoft 365 Business Standard EEA (no Teams)"
            "Microsoft_365_ Business_ Premium_(no Teams)" = "Microsoft 365 Business Premium (no Teams)"
            "Microsoft_365_Business_Premium_Donation_(Non_Profit_Pricing)" = "Microsoft 365 Business Premium Donation"
            "SMB_BUSINESS_PREMIUM" = "Microsoft 365 Business Standard - Prepaid Legacy"
            "Microsoft_365_Business_Basic_(no Teams)" = "Microsoft 365 Business Basic (no Teams)"
            "ENTERPRISEPACK"             = "Office 365 E3"
            "ENTERPRISEPREMIUM"          = "Office 365 E5"
            "SPE_E3"                     = "Microsoft 365 E3"
            "SPE_E5"                     = "Microsoft 365 E5"
            "O365_BUSINESS_ESSENTIALS"   = "Microsoft 365 Business Basic"
            "O365_BUSINESS"              = "Microsoft 365 Apps for Business"
            "OFFICESUBSCRIPTION"         = "Microsoft 365 Apps for Enterprise"
            "WOFF_MIDMARKET"             = "Microsoft 365 F3"
            # Exchange standalone SKUs
            "EXCHANGESTANDARD"           = "Exchange Online (Plan 1)"
            "EXCHANGEENTERPRISE"         = "Exchange Online (Plan 2)"
            "EXCHANGEESSENTIALS"         = "Exchange Online Essentials"
            "EXCHANGEDESKLESS"           = "Exchange Online Kiosk"
            # Service protection add‑ons
            "EXCHANGEARCHIVE_ADDON"      = "Exchange Online Archiving (Online)"
            "EOP_ENTERPRISE"             = "Exchange Online Protection"
            # SharePoint standalone
            "SHAREPOINTENTERPRISE"       = "SharePoint Online (Plan 2)"
            "SHAREPOINTLITE"             = "SharePoint Online (Plan 1)"
            "SHAREPOINTDESKLESS"         = "SharePoint Online Kiosk"
            # Others
            "INTUNE_A"                   = "Microsoft Intune"
            "INTUNE_O365"                = "Intune for Office 365"
            "EMS"                        = "Enterprise Mobility + Security E3"
            "EMSPREMIUM"                 = "Enterprise Mobility + Security E5"
            "POWER_BI_PRO"               = "Power BI Pro"
            "FLOW_FREE"                  = "Power Automate Free"
            "FLOW_P1"                    = "Power Automate Plan 1"
            "FLOW_P2"                    = "Power Automate Plan 2"
        }


        # --- List of SKUs that include a mailbox (these should be top-level SKUs) ---
        $skusWithMailbox = @(
        "O365_BUSINESS_ESSENTIALS",
        "O365_BUSINESS_PREMIUM",
        "ENTERPRISEPACK",     
        "ENTERPRISEPREMIUM",   
        "SPE_E3",
        "SPE_E5",
        "EXCHANGESTANDARD",
        "SPB",
        "EXCHANGEENTERPRISE",
        "EXCHANGESTANDARD_GOV",
        "EXCHANGEENTERPRISE_GOV",
        "EXCHANGEENTERPRISE_FACULTY",
        "EXCHANGEESSENTIALS",
        "EXCHANGEDESKLESS",
        "O365_BUSINESS",
        "MICROSOFT_365_BUSINESS_STANDARD_NO_TEAMS",
        "Microsoft_365_Business_Standard_EEA_(no_Teams)",
        "Microsoft_365_ Business_ Premium_(no Teams)",
        "Microsoft_365_Business_Premium_Donation_(Non_Profit_Pricing)",
        "SMB_BUSINESS_PREMIUM",
        "Microsoft_365_Business_Basic_(no Teams)"
        )

        #Get all users and their assigned licenses
        $users = Get-MgUser -All -Property "displayName,userPrincipalName,accountEnabled,assignedLicenses"
    }
    catch {
        Write-Error "Failed to retrieve initial user or license information. Error: $_"
        return $null
    }

    $licenseData = @()
    foreach ($user in $users) {
        if (-not $user.AssignedLicenses) {
            # Add an entry for users with no licenses
            $licenseData += [PSCustomObject]@{
                DisplayName     = $user.DisplayName
                UPN             = $user.UserPrincipalName
                AccountEnabled  = $user.AccountEnabled
                License         = "No Licenses Assigned"
                AssignedBy      = "N/A"
                ExchangeMailbox = '❌'
            }
            continue
        }

        # Determine the primary assigned license(s) and check for mailbox
        $userAssignedMainLicenses = @()
        $hasMailboxLicense = $false

        foreach ($license in $user.AssignedLicenses) {
            $skuPartNumber = $skuIdToPartNumberMap[$license.SkuId]

            # If the SKU is a top-level license, add it to the list of main licenses
            # and check if it provides a mailbox.
            if ($skusWithMailbox -contains $skuPartNumber) {
                $hasMailboxLicense = $true
            }

            $friendlyLicenseName = if ($friendlyNameMap.ContainsKey($skuPartNumber)) {
                                       $friendlyNameMap[$skuPartNumber]
                                   } elseif ($skuDisplayNameMap.ContainsKey($skuPartNumber)) {
                                       $skuDisplayNameMap[$skuPartNumber]
                                   } else {
                                       $skuPartNumber
                                   }

            $userAssignedMainLicenses += $friendlyLicenseName
        }

        # Report only unique, primary licenses for the user
        $uniqueMainLicenses = $userAssignedMainLicenses | Select-Object -Unique

        foreach ($mainLicense in $uniqueMainLicenses) {
            $licenseData += [PSCustomObject]@{
                DisplayName     = $user.DisplayName
                UPN             = $user.UserPrincipalName
                AccountEnabled  = $user.AccountEnabled
                License         = $mainLicense
                AssignedBy      = "Direct" # Note: Group-based assignment details are not available here
                ExchangeMailbox = if ($hasMailboxLicense) { '✅' } else { '❌' }
            }
        }
    }

    # The previous unique sorting was good, keep it for final output
    $uniqueLicenseData = $licenseData | Sort-Object -Property UPN, License -Unique

    Write-Host "Successfully processed license information for $($users.Count) users." -ForegroundColor Green
    return $uniqueLicenseData
}