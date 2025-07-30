<#
Written by Harry Shelton - 2025
Script Name: AetherCred-Core.ps1
Version: 3.2
Description: Main orchestration script for the AetherCred reporting tool - Using App Auth Only
You must have the Graph Beta Module installed for this tool to work fully!!

Designed for the following modules:
Run-ConditionalAccessReview.ps1
Run-GroupReview.ps1
Run-LicensingReview.ps1
Run-SecurityReview.ps1
Run-ServicePrincipalReview.ps1
Run-GuestUserReview.ps1
Run-SharedMailboxReview.ps1
Run-DistributionListReview.ps1

#>

# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

# ==============================================================================
# CONFIGURATION FILE SETTINGS
# ==============================================================================
$ConfigFile = Join-Path $scriptFolder "AetherCred.config"

# ==============================================================================
# HELPER FUNCTION: Process and Export Report
# ==============================================================================
function Process-And-ExportReport {
    param(
        $RawReportData,
        [Parameter(Mandatory=$true)]
        [string]$ReportBaseName,
        [Parameter(Mandatory=$true)]
        [string]$ReportType
    )

    $reportDataForExport = @() #Initialize as an empty array
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

    Write-Host "Processing and exporting $($ReportType) results..." -ForegroundColor Yellow

    if ($null -eq $RawReportData -or ($RawReportData | Measure-Object -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Warning "No data returned for $($ReportType)."
        
        $placeholderObject = $null
        if ($ReportType -eq "Guest User Review") {
            $placeholderObject = [PSCustomObject]@{
                DisplayName    = "No Guest Users Found in Tenant"
                Email          = "N/A"
                MFAStatus      = "N/A"
                LastSignInDate = "N/A"
                CreatedDate    = "N/A"
            }
        } elseif ($ReportType -eq "Shared Mailbox Review") {
            $placeholderObject = [PSCustomObject]@{
                DisplayName        = "No Shared Mailboxes Found"
                Email              = "N/A"
                CreatedDate        = "N/A"
            }
        } elseif ($ReportType -eq "Distribution List Review") {
            $placeholderObject = [PSCustomObject]@{
                DisplayName           = "No Distribution Lists Found"
                Email                 = "N/A"
                CreatedDate           = "N/A"
                AllowExternalSenders  = "N/A"
            }
        }

        if ($null -ne $placeholderObject) {
            $reportDataForExport = @($placeholderObject)
        }
    }
    else {
        #Ensure the data is always treated as an array, even if only one item is returned from the module.
        $reportDataForExport = @($RawReportData) | ForEach-Object {
            $newItem = $_ | Select-Object *
            foreach ($prop in $newItem.PSObject.Properties) {
                if ($prop.Value -is [DateTime]) {
                    $newItem.($prop.Name) = ($prop.Value).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
            $newItem
        }
    }

    Write-Host "$($ReportType) returned $($reportDataForExport.Count) items. Converting to JSON array." -ForegroundColor Green
    
    #Explicitly handle all cases to ensure the output is always a valid JSON array.
    if ($reportDataForExport.Count -eq 0) {
        $jsonArrayContent = "[]"
    } elseif ($reportDataForExport.Count -eq 1) {
        #Manually build the array string for a single item to guarantee the format.
        $singleItemJson = $reportDataForExport[0] | ConvertTo-Json -Depth 5 -Compress
        $jsonArrayContent = "[$singleItemJson]"
    } else {
        #Multiple items can be converted directly.
        $jsonArrayContent = $reportDataForExport | ConvertTo-Json -Depth 5 -Compress
    }

    $jsContent = ""
    switch ($ReportBaseName) {
        "AetherCred-Data"                 { $jsContent = "const aetherCredData = $($jsonArrayContent);`nconst lastUpdated = `"$($timestamp)`";" }
        "AetherCred-CA-Data"              { $jsContent = "const aetherCredCAData = $($jsonArrayContent);`nconst lastUpdatedCA = `"$($timestamp)`";" }
        "AetherCred-License-Data"         { $jsContent = "const aetherCredLicenseData = $($jsonArrayContent);`nconst lastUpdatedLicense = `"$($timestamp)`";" }
        "AetherCred-Group-Data"           { $jsContent = "const aetherCredGroupData = $($jsonArrayContent);`nconst lastUpdatedGroup = `"$($timestamp)`";" }
        "AetherCred-SP-Data"              { $jsContent = "const aetherCredSPData = $($jsonArrayContent);`nconst lastUpdatedSP = `"$($timestamp)`";" }
        "AetherCred-Guest-Data"           { $jsContent = "const aetherCredGuestData = $($jsonArrayContent);`nconst lastUpdatedGuest = `"$($timestamp)`";" }
        "AetherCred-Shared-Mailbox-Data"  { $jsContent = "const aetherCredSharedMailboxData = $($jsonArrayContent);`nconst lastUpdatedSharedMailbox = `"$($timestamp)`";" }
        "AetherCred-DL-Data"              { $jsContent = "const aetherCredDLData = $($jsonArrayContent);`nconst lastUpdatedDL = `"$($timestamp)`";" }
    }

    #Define and create export directories
    $jsExportFolder = Join-Path $scriptFolder "TenantData"
    $csvExportFolder = Join-Path $scriptFolder "CSV-Export"
    if (-not (Test-Path $jsExportFolder)) { New-Item -ItemType Directory -Path $jsExportFolder | Out-Null }
    if (-not (Test-Path $csvExportFolder)) { New-Item -ItemType Directory -Path $csvExportFolder | Out-Null }

    #Update file paths to use the export folders
    $jsFilePath = Join-Path $jsExportFolder "$($ReportBaseName).js"
    $csvFilePath = Join-Path $csvExportFolder "$($ReportBaseName).csv"
    
    $jsContent | Out-File -Encoding UTF8 -FilePath $jsFilePath -Force
    Write-Host "JS data exported to '$jsFilePath'" -ForegroundColor DarkCyan
    
    if ($null -ne $reportDataForExport -and $reportDataForExport.Count -gt 0) {
        $csvData = $reportDataForExport | ForEach-Object {
            $props = $_.PSObject.Properties
            $outputObject = [ordered]@{}
            foreach ($prop in $props) {
                if ($prop.Value -is [array]) {
                    $outputObject[$prop.Name] = $prop.Value -join '; '
                } else {
                    $outputObject[$prop.Name] = $prop.Value
                }
            }
            [PSCustomObject]$outputObject
        }
        $csvData | Export-Csv -Path $csvFilePath -NoTypeInformation -Force
        Write-Host "CSV data exported to '$csvFilePath'" -ForegroundColor DarkCyan
    }
    else {
        Write-Host "No CSV data to export for $($ReportType)." -ForegroundColor Yellow
    }
}


# ==============================================================================
# MAIN SCRIPT BODY STARTS HERE :D
# ==============================================================================
try {
    # ==========================================================================
    # LOAD REVIEW MODULES
    # ==========================================================================
    Write-Host "Loading review modules..."
    $modulePath = Join-Path $scriptFolder "Modules"
    . (Join-Path $modulePath "Run-SecurityReview.ps1")
    . (Join-Path $modulePath "Run-ConditionalAccessReview.ps1")
    . (Join-Path $modulePath "Run-LicensingReview.ps1")
    . (Join-Path $modulePath "Run-GroupReview.ps1")
    . (Join-Path $modulePath "Run-ServicePrincipalReview.ps1")
    . (Join-Path $modulePath "Run-GuestUserReview.ps1")
    . (Join-Path $modulePath "Run-SharedMailboxReview.ps1")
    . (Join-Path $modulePath "Run-DistributionListReview.ps1")

    # ==========================================================================
    # GET CREDENTIALS FROM CONFIGURATION FILE
    # ==========================================================================
    Write-Host "Retrieving credentials from configuration file: '$ConfigFile'..."

    if (-not (Test-Path $ConfigFile)) {
        throw "Configuration file not found at '$ConfigFile'. Please create it with the required credentials."
    }

    $config = Get-Content $ConfigFile | ConvertFrom-StringData
    $AppId = $config.AETHERCRED_APP_ID
    $TenantId = $config.AETHERCRED_TENANT_ID
    $ClientSecret = $config.AETHERCRED_CLIENT_SECRET
    
    if ([string]::IsNullOrWhiteSpace($AppId) -or [string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
        throw "One or more required credentials are not found in '$ConfigFile'."
    }
    
    $SecureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($AppId, $SecureClientSecret)


    # ==========================================================================
    # START THE CONNECTION TO ENTRA
    # ==========================================================================
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green

    # ==========================================================================
    # MENU POP UP - WILL START WHICH REVIEW YOU SELECT
    # ==========================================================================
    while ($true) {
        $menu = @{ 
            '1'='Security Review'; 
            '2'='Conditional Access Review'; 
            '3'='Licensing Review'; 
            '4'='Group Review';
            '5'='Service Principal Review';
            '6'='Guest User Review';
            '7'='Shared Mailbox Review';
            '8'='Distribution List Review';
            'A'='Run ALL Reviews';
            'Q'='Quit' 
        }
        do {
            Clear-Host
            Write-Host "`n====================================="
            Write-Host "   AetherCred - Tenant Review Menu"
            Write-Host "====================================="
            $menu.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host "$($_.Name): $($_.Value)" }
            Write-Host "-------------------------------------"
            $userChoice = (Read-Host "`nPlease select an option").ToUpper()
            if (-not $menu.ContainsKey($userChoice)) { Write-Host "Invalid selection." -ForegroundColor Red; Start-Sleep 2 }
        } while (-not $menu.ContainsKey($userChoice))

        if ($userChoice -eq 'Q') { break }

        $launchDashboardAfterRun = $false

        # 'RUN ALL' LOGIC 
        if ($userChoice -eq 'A') { #Run All Reviews
            Write-Host "`nInitiating ALL AetherCred Reviews..." -ForegroundColor Green
            
            $securityData = Invoke-SecurityReview
            Process-And-ExportReport -RawReportData $securityData -ReportBaseName "AetherCred-Data" -ReportType "Security Review"

            $caData = Invoke-ConditionalAccessReview
            Process-And-ExportReport -RawReportData $caData -ReportBaseName "AetherCred-CA-Data" -ReportType "Conditional Access Review"

            $licenseData = Invoke-LicensingReview
            Process-And-ExportReport -RawReportData $licenseData -ReportBaseName "AetherCred-License-Data" -ReportType "Licensing Review"

            $groupData = Invoke-GroupReview
            Process-And-ExportReport -RawReportData $groupData -ReportBaseName "AetherCred-Group-Data" -ReportType "Group Review"

            $spData = Invoke-ServicePrincipalReview
            Process-And-ExportReport -RawReportData $spData -ReportBaseName "AetherCred-SP-Data" -ReportType "Service Principal Review"
            
            $guestData = Invoke-GuestUserReview
            Process-And-ExportReport -RawReportData $guestData -ReportBaseName "AetherCred-Guest-Data" -ReportType "Guest User Review"

            $mailboxData = Invoke-SharedMailboxReview
            Process-And-ExportReport -RawReportData $mailboxData -ReportBaseName "AetherCred-Shared-Mailbox-Data" -ReportType "Shared Mailbox Review"

            $dlData = Invoke-DistributionListReview
            Process-And-ExportReport -RawReportData $dlData -ReportBaseName "AetherCred-DL-Data" -ReportType "Distribution List Review"

            Write-Host "`nAll reviews processed and exported." -ForegroundColor Green
            $launchDashboardAfterRun = $true
        }
        else { #Individual report selection
            $reportDetails = @{
                '1' = @{ BaseName = "AetherCred-Data";                 Type = "Security Review";           Action = { Invoke-SecurityReview } }
                '2' = @{ BaseName = "AetherCred-CA-Data";              Type = "Conditional Access Review"; Action = { Invoke-ConditionalAccessReview } }
                '3' = @{ BaseName = "AetherCred-License-Data";         Type = "Licensing Review";          Action = { Invoke-LicensingReview } }
                '4' = @{ BaseName = "AetherCred-Group-Data";           Type = "Group Review";              Action = { Invoke-GroupReview } }
                '5' = @{ BaseName = "AetherCred-SP-Data";              Type = "Service Principal Review";  Action = { Invoke-ServicePrincipalReview } }
                '6' = @{ BaseName = "AetherCred-Guest-Data";           Type = "Guest User Review";         Action = { Invoke-GuestUserReview } }
                '7' = @{ BaseName = "AetherCred-Shared-Mailbox-Data";  Type = "Shared Mailbox Review";     Action = { Invoke-SharedMailboxReview } }
                '8' = @{ BaseName = "AetherCred-DL-Data";              Type = "Distribution List Review";  Action = { Invoke-DistributionListReview } }
            }
            $selectedReport = $reportDetails[$userChoice]
            $rawReportData = & $selectedReport.Action
            
            Process-And-ExportReport -RawReportData $rawReportData -ReportBaseName $selectedReport.BaseName -ReportType $selectedReport.Type
            $launchDashboardAfterRun = $true
        }

        if ($launchDashboardAfterRun) {
            $reportHtmlPath = Join-Path $scriptFolder "AetherCred-Report.html"
            if (Test-Path $reportHtmlPath) {
                Write-Host "Launching report..." -ForegroundColor Green
                Start-Process $reportHtmlPath
            } else {
                Write-Warning "Report HTML file not found at '$reportHtmlPath'. Cannot launch."
            }
        }
        Read-Host "`nPress Enter to return to the menu..."
    }

    Write-Host "Script finished."
}
catch {
    Write-Error "A critical error occurred. Error: $($_.Exception.Message)"
}
finally {
    if (Get-MgContext) {
        Write-Host "Disconnecting from Microsoft Graph."
        Disconnect-MgGraph
    }
}
