<#
Written by Harry Shelton - 2025
Script Name: AetherCred-Core.ps1
Version: 3.1
Description: Main orchestration script for the AetherCred reporting tool - Using App Auth Only
You must have the Graph Beta Module installed for this tool to work fully!!

Designed for the following modules:
Run-ConditionalAccessReview.ps1
Run-GroupReview.ps1
Run-LicensingReview.ps1
Run-SecurityReview.ps1

#>

# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================
$AppName = "AetherCred"
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
        [Parameter(Mandatory=$true)]
        $RawReportData,
        [Parameter(Mandatory=$true)]
        [string]$ReportBaseName,
        [Parameter(Mandatory=$true)]
        [string]$ReportType
    )

    $jsonArrayContent = $null
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

    Write-Host "Processing and exporting $($ReportType) results..." -ForegroundColor Yellow

    if ($null -eq $RawReportData -or ($RawReportData | Measure-Object -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Warning "No data returned for $($ReportType)."
        $jsonArrayContent = "[]"
        $reportDataForExport = @()
    }
    else {
        #Pre-process the data to ensure dates are in the correct ISO 8601 string format for JSON - dates will break in the reporting if you change this :(
        $processedData = foreach ($item in $RawReportData) {
            $newItem = $item | Select-Object *
            foreach ($prop in $newItem.PSObject.Properties) {
                if ($prop.Value -is [DateTime]) {
                    $newItem.($prop.Name) = ($prop.Value).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
            $newItem
        }

        #Use the pre-processed data for all exports.
        $reportDataForExport = $processedData
        $itemCount = ($processedData | Measure-Object).Count
        Write-Host "$($ReportType) returned $($itemCount) items. Converting to JSON array." -ForegroundColor Green
        
        #Ensure the output is always a JSON array
        if ($itemCount -eq 1) {
            $singleItemJson = $processedData | ConvertTo-Json -Depth 5 -Compress
            $jsonArrayContent = "[$singleItemJson]"
        }
        else {
            $jsonArrayContent = $processedData | ConvertTo-Json -Depth 5 -Compress
        }
    }

    $jsContent = ""
    switch ($ReportBaseName) {
        "AetherCred-Data"         { $jsContent = "const aetherCredData = $($jsonArrayContent);`nconst lastUpdated = `"$($timestamp)`";" }
        "AetherCred-CA-Data"      { $jsContent = "const aetherCredCAData = $($jsonArrayContent);`nconst lastUpdatedCA = `"$($timestamp)`";" }
        "AetherCred-License-Data" { $jsContent = "const aetherCredLicenseData = $($jsonArrayContent);`nconst lastUpdatedLicense = `"$($timestamp)`";" }
        "AetherCred-Group-Data"   { $jsContent = "const aetherCredGroupData = $($jsonArrayContent);`nconst lastUpdatedGroup = `"$($timestamp)`";" }
    }

    $jsFilePath = Join-Path $scriptFolder "$($ReportBaseName).js"
    $csvFilePath = Join-Path $scriptFolder "$($ReportBaseName).csv"
    
    $jsContent | Out-File -Encoding UTF8 -FilePath $jsFilePath -Force
    Write-Host "JS data exported to '$jsFilePath'" -ForegroundColor DarkCyan
    
    if ($null -ne $reportDataForExport -and $reportDataForExport.Count -gt 0) {
        # For CSV export, flatten any array properties to make the CSV readable
        $csvData = $reportDataForExport | ForEach-Object {
            $props = $_.PSObject.Properties
            $outputObject = [ordered]@{}
            foreach ($prop in $props) {
                if ($prop.Value -is [array]) {
                    $outputObject[$prop.Name] = $prop.Value -join '; ' # Join array elements with a semicolon
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

    # ==========================================================================
    # GET CREDENTIALS FROM CONFIGURATION FILE
    # ==========================================================================
    Write-Host "Retrieving credentials from configuration file: '$ConfigFile'..."

    if (-not (Test-Path $ConfigFile)) {
        throw "Configuration file not found at '$ConfigFile'. Please create it with the required credentials."
    }

    #This section is the calling for the App details, you need to make sure the AetherCred.config exists within the same folder!
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
            'A'='Run ALL Reviews'; # <-- UPDATED TEXT
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

        # --- UPDATED 'RUN ALL' LOGIC ---
        if ($userChoice -eq 'A') { #Run All Reviews
            Write-Host "`nInitiating ALL AetherCred Reviews..." -ForegroundColor Green
            
            #Security Review
            $securityData = Invoke-SecurityReview
            if ($null -ne $securityData) {
                Process-And-ExportReport -RawReportData $securityData -ReportBaseName "AetherCred-Data" -ReportType "Security Review"
            }

            #Conditional Access Review
            $caData = Invoke-ConditionalAccessReview
            if ($null -ne $caData) {
                Process-And-ExportReport -RawReportData $caData -ReportBaseName "AetherCred-CA-Data" -ReportType "Conditional Access Review"
            }

            #Licensing Review
            $licenseData = Invoke-LicensingReview
            if ($null -ne $licenseData) {
                Process-And-ExportReport -RawReportData $licenseData -ReportBaseName "AetherCred-License-Data" -ReportType "Licensing Review"
            }

            #Group Review
            $groupData = Invoke-GroupReview
            if ($null -ne $groupData) {
                Process-And-ExportReport -RawReportData $groupData -ReportBaseName "AetherCred-Group-Data" -ReportType "Group Review"
            }
            
            Write-Host "`nAll reviews processed and exported." -ForegroundColor Green
            $launchDashboardAfterRun = $true
        }
        else { #Individual report selection
            $reportDetails = @{
                '1' = @{ BaseName = "AetherCred-Data";         Type = "Security Review";           Action = { Invoke-SecurityReview } }
                '2' = @{ BaseName = "AetherCred-CA-Data";      Type = "Conditional Access Review"; Action = { Invoke-ConditionalAccessReview } }
                '3' = @{ BaseName = "AetherCred-License-Data"; Type = "Licensing Review";          Action = { Invoke-LicensingReview } }
                '4' = @{ BaseName = "AetherCred-Group-Data";   Type = "Group Review";              Action = { Invoke-GroupReview } }
            }
            $selectedReport = $reportDetails[$userChoice]
            $rawReportData = & $selectedReport.Action
            #This check prevents the crash on individual runs as well - please no remove, it will break the flow of the report/review.
            if ($null -ne $rawReportData) {
                Process-And-ExportReport -RawReportData $rawReportData -ReportBaseName $selectedReport.BaseName -ReportType $selectedReport.Type
                $launchDashboardAfterRun = $true
            }
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
