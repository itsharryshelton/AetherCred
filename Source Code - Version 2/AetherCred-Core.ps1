<#
Written by Harry Shelton - 2025
Script Name: AetherCred Core
Version: 2
Description: Main orchestration script for the AetherCred reporting tool.
#>

# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================
$AppName = "AetherCred"
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

# ==============================================================================
# HELPER FUNCTION: Process and Export a Single Report
# ==============================================================================
function Process-And-ExportReport {
    param(
        [Parameter(Mandatory=$true)]
        $RawReportData,
        [Parameter(Mandatory=$true)]
        [string]$ReportBaseName, # "AetherCred-Data", "AetherCred-CA-Data", "AetherCred-License-Data"
        [Parameter(Mandatory=$true)]
        [string]$ReportType
    )

    #Variables for the final data collection and JSON string
    $reportDataForExport = $null
    $jsonArrayContent = $null
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

    Write-Host "Processing and exporting $($ReportType) results..." -ForegroundColor Yellow

    # --- PS 5.1 JSON Array Logic ---
    if ($null -eq $RawReportData -or ($RawReportData | Measure-Object -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Warning "No data returned for $($ReportType)."
        $jsonArrayContent = "[]"
        $reportDataForExport = @()
    } elseif (($RawReportData | Measure-Object -ErrorAction SilentlyContinue).Count -eq 1 -and $ReportType -eq "Conditional Access Review") {
        $singleObjectJson = $RawReportData | ConvertTo-Json -Depth 5 -Compress
        $jsonArrayContent = "[$singleObjectJson]"
        $reportDataForExport = @($RawReportData)
    } else {
        Write-Host "$($ReportType) returned $(($RawReportData | Measure-Object -ErrorAction SilentlyContinue).Count) items. Converting to JSON array." -ForegroundColor Green
        $jsonArrayContent = $RawReportData | ConvertTo-Json -Depth 5 -Compress
        $reportDataForExport = $RawReportData
    }
    # --- End PS 5.1 JSON Array Logic ---

    #Construct the full JavaScript content string based on ReportBaseName
    $jsContent = ""
    switch ($ReportBaseName) {
        "AetherCred-Data" {
            $jsContent = "const aetherCredData = $($jsonArrayContent);`nconst lastUpdated = `"$($timestamp)`";"
        }
        "AetherCred-CA-Data" {
            $jsContent = "const aetherCredCAData = $($jsonArrayContent);`nconst lastUpdatedCA = `"$($timestamp)`";"
        }
        "AetherCred-License-Data" {
            $jsContent = "const aetherCredLicenseData = $($jsonArrayContent);`nconst lastUpdatedLicense = `"$($timestamp)`";"
        }
    }

    $jsFilePath = Join-Path $scriptFolder "$($ReportBaseName).js"
    $csvFilePath = Join-Path $scriptFolder "$($ReportBaseName).csv"
    
    #Write the JavaScript content to the .js file
    $jsContent | Out-File -Encoding UTF8 -FilePath $jsFilePath -Force
    Write-Host "JS data exported to '$jsFilePath'" -ForegroundColor DarkCyan
    
    #Only export CSV if there is actual data in the collection
    if ($null -ne $reportDataForExport -and $reportDataForExport.Count -gt 0) {
        $reportDataForExport | Export-Csv -Path $csvFilePath -NoTypeInformation -Force
        Write-Host "CSV data exported to '$csvFilePath'" -ForegroundColor DarkCyan
    } else {
        Write-Host "No CSV data to export for $($ReportType)." -ForegroundColor Yellow
    }
}


# ==============================================================================
# MAIN SCRIPT BODY
# ==============================================================================
try {
    # ==========================================================================
    # STEP 1: LOAD MODULES
    # ==========================================================================
    Write-Host "Loading review modules..."
    $modulePath = Join-Path $scriptFolder "Modules"
    . (Join-Path $modulePath "Run-SecurityReview.ps1")
    . (Join-Path $modulePath "Run-ConditionalAccessReview.ps1")
    . (Join-Path $modulePath "Run-LicensingReview.ps1")

    # ==========================================================================
    # STEP 2: GET OR CREATE THE AETHERCRED APP & ESTABLISH CONNECTION
    # ==========================================================================
    Write-Host "Checking for '$AppName' Enterprise Application..."
    $appId = $null
    $tenantId = $null
    $HomePageURL = "https://aethercred.co.uk/"
    $AppDescription = "AetherCred is an open-source tool that provides insights into your Entra ID tenant, helping you learn best practices, find misconfigurations, and enforce secure identity policies."
    $LogoUrl = "https://images.aethercred.co.uk/AetherCredLogoCloudEntraSize.png"

    # Connect with minimal permissions to manage the application
    Connect-MgGraph -Scopes "Application.ReadWrite.All", "Organization.Read.All" -NoWelcome
    $tenantId = (Get-MgContext).TenantId
    Write-Host "Operating in Tenant: $tenantId"

    # Define the required API permissions for the app manifest
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
    $requiredScopes = @("User.Read.All", "Directory.Read.All", "UserAuthenticationMethod.Read.All", "AuditLog.Read.All", "Reports.Read.All", "Policy.Read.All", "Organization.Read.All")
    
    $resourceAccessList = @()
    foreach ($scope in $requiredScopes) {
        $permission = $graphSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scope }
        if ($permission) {
            $resourceAccessList += @{ Id = $permission.Id; Type = "Scope" }
        }
    }

    if ($resourceAccessList.Count -ne $requiredScopes.Count) {
        Write-Error "Failed to build the required permission list. Cannot proceed."
        return
    }
    $requiredResourceAccess = @( @{ ResourceAppId = $graphSp.AppId; ResourceAccess = $resourceAccessList } )

    # Get the existing application, explicitly requesting the AppId property
    $existingApp = Get-MgApplication -Filter "displayName eq '$AppName'" -Property "appId,publicClient,web"
    
    if ($null -eq $existingApp) {
        Write-Host "'$AppName' application not found. Creating it now..." -ForegroundColor Yellow
        $appParams = @{ 
            DisplayName = $AppName; Description = $AppDescription; SignInAudience = "AzureADMyOrg";
            PublicClient = @{ RedirectUris = "http://localhost" }; Web = @{ HomePageUrl = $HomePageURL };
            RequiredResourceAccess = $requiredResourceAccess
        }
        $app = New-MgApplication -BodyParameter $appParams
        Write-Host "Successfully created Application Registration." -ForegroundColor Green
        
        try {
            $tempLogoPath = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName() + ".png")
            Invoke-WebRequest -Uri $LogoUrl -OutFile $tempLogoPath -UseBasicParsing
            Set-MgApplicationLogo -ApplicationId $app.Id -InFile $tempLogoPath
            Write-Host "Custom logo uploaded successfully." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to download or upload logo."
        } finally {
            if (Test-Path -Path $tempLogoPath) { Remove-Item $tempLogoPath -Force }
        }

        New-MgServicePrincipal -AppId $app.AppId | Out-Null
        Write-Host "Successfully created Service Principal." -ForegroundColor Green
        Write-Host "Pausing for 20 seconds for Entra ID replication..." -ForegroundColor Cyan
        Start-Sleep -Seconds 20
        $appId = $app.AppId
        
    } else {
        Write-Host "'$AppName' application already exists. Verifying configuration..." -ForegroundColor Green
        
        $updateParams = @{}
        if (-not ($existingApp.PublicClient.RedirectUris -contains "http://localhost")) {
            $updateParams.PublicClient = @{ RedirectUris = "http://localhost" }
        }
        if ($existingApp.Web.HomePageUrl -ne $HomePageURL) {
            $updateParams.Web = @{ HomePageUrl = $HomePageURL }
        }

        if ($updateParams.Count -gt 0) {
            Write-Host "Application properties are incorrect. Updating..." -ForegroundColor Yellow
            Update-MgApplication -ApplicationId $existingApp.Id -BodyParameter $updateParams
            Write-Host "Application successfully updated." -ForegroundColor Green
        }
        
        $appId = $existingApp.AppId
    }
    
    #Disconnect the temporary app management session
    Disconnect-MgGraph

    #Establish the main connection using the AetherCred App ID
    Write-Host "Connecting to Microsoft Graph using the '$AppName' application context ($appId)..."
    Connect-MgGraph -AppId $appId -TenantId $tenantId -NoWelcome -Scopes $requiredScopes

    # ==========================================================================
    # TRIGGER REVIEWS FROM MENU
    # ==========================================================================
    while ($true) {
        $menu = @{ '1'='Security Review'; '2'='Conditional Access Review'; '3'='Licensing Review'; 'A'='Run ALL Reviews'; 'Q'='Quit' }
        do {
            Clear-Host
            Write-Host "====================================="; Write-Host "   AetherCred - Tenant Review Menu"; Write-Host "====================================="
            $menu.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host "$($_.Name): $($_.Value)" }
            Write-Host "-------------------------------------"; Write-Host
            $userChoice = (Read-Host "Please select an option").ToUpper()
            if (-not $menu.ContainsKey($userChoice)) { Write-Host "Invalid selection." -ForegroundColor Red; Start-Sleep 2 }
        } while (-not $menu.ContainsKey($userChoice))

        if ($userChoice -eq 'Q') { break }

        $launchDashboardAfterRun = $false

        if ($userChoice -eq 'A') { # Run All Reviews
            Write-Host "`nInitiating ALL AetherCred Reviews..." -ForegroundColor Green
            
            # --- Security Review ---
            Process-And-ExportReport -RawReportData (Invoke-SecurityReview) -ReportBaseName "AetherCred-Data" -ReportType "Security Review"

            # --- Conditional Access Review ---
            Process-And-ExportReport -RawReportData (Invoke-ConditionalAccessReview) -ReportBaseName "AetherCred-CA-Data" -ReportType "Conditional Access Review"

            # --- Licensing Review ---
            Process-And-ExportReport -RawReportData (Invoke-LicensingReview) -ReportBaseName "AetherCred-License-Data" -ReportType "Licensing Review"
            
            Write-Host "`nAll reviews processed and exported." -ForegroundColor Green
            $launchDashboardAfterRun = $true
        }
        else { # Individual report selection (1, 2, or 3)
            # Variables for individual report runs, passed to the helper function
            $rawReportData = $null
            $reportBaseName = ""
            $reportType = ""

            switch ($userChoice) {
                '1' { 
                    $rawReportData = Invoke-SecurityReview
                    $reportBaseName = "AetherCred-Data"
                    $reportType = "Security Review"
                }
                '2' { 
                    $rawReportData = Invoke-ConditionalAccessReview
                    $reportBaseName = "AetherCred-CA-Data"
                    $reportType = "Conditional Access Review"
                }
                '3' {
                    $rawReportData = Invoke-LicensingReview
                    $reportBaseName = "AetherCred-License-Data"
                    $reportType = "Licensing Review"
                }
            }
            # Process and export the selected individual report
            Process-And-ExportReport -RawReportData $rawReportData -ReportBaseName $reportBaseName -ReportType $reportType
            $launchDashboardAfterRun = $true # Indicate that report should be launched
        }

        # ==========================================================================
        # LAUNCH REPORT
        # ==========================================================================
        if ($launchDashboardAfterRun) {
            $reportHtmlPath = Join-Path $scriptFolder "AetherCred-Report.html"
            if (Test-Path $reportHtmlPath) { 
                Write-Host "Launching report..." -ForegroundColor Green
                Start-Process $reportHtmlPath 
            } else {
                Write-Warning "Report HTML file not found at '$reportHtmlPath'. Cannot launch."
            }
        }
        
        Read-Host "Press Enter to return to the menu..."
    }

    Write-Host "Script finished."

} 
catch {
    Write-Error "A critical error occurred. Error: $_"
}
finally {
    if (Get-MgContext) {
        Write-Host "Disconnecting from Microsoft Graph."
        Disconnect-MgGraph
    }
}
