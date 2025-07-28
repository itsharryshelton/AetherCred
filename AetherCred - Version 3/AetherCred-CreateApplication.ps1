<#
Written by Harry Shelton - 2025
Script Name: AetherCred-CreateApplication.ps1
Version: 1
Description: Creates the App Registration for you, you must still create the secret and grant admin consent!
You must have the Graph Module installed for this tool to work fully!
#>

Connect-MgGraph -Scopes "Application.ReadWrite.All"

Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green

#Configuration Variables
$appName = "AetherCred" #You can change this back to your test name if needed
$homepageUrl = "https://aethercred.co.uk/"
$logoUrl = "https://images.aethercred.co.uk/AetherCredLogoCloudEntraSize.png"
$tempLogoPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "AetherCredLogoCloudEntraSize.png")

#Define the required API permissions
Write-Host "Defining API permissions for Microsoft Graph..."

#Get the Service Principal for Microsoft Graph (Resource App)
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

#List the permissions you need
$requiredAppPermissions = @(
    "Application.Read.All", "AuditLog.Read.All", "Directory.Read.All",
    "Domain.Read.All", "Organization.Read.All", "Policy.Read.All",
    "Reports.Read.All", "User.Read.All", "UserAuthenticationMethod.Read.All"
)
$requiredDelegatedPermissions = @("User.Read")

#Build the list of permission IDs for the request body
$permissionGrantList = @()
$requiredAppPermissions | ForEach-Object {
    $permissionName = $_
    $permissionId = $graphSp.AppRoles | Where-Object { $_.Value -eq $permissionName } | Select-Object -ExpandProperty Id
    if ($permissionId) { $permissionGrantList += @{ "Id" = $permissionId; "Type" = "Role" } }
    else { Write-Warning "Could not find Application permission: $permissionName" }
}
$requiredDelegatedPermissions | ForEach-Object {
    $permissionName = $_
    $permissionId = $graphSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $permissionName } | Select-Object -ExpandProperty Id
    if ($permissionId) { $permissionGrantList += @{ "Id" = $permissionId; "Type" = "Scope" } }
    else { Write-Warning "Could not find Delegated permission: $permissionName" }
}

$requiredResourceAccess = @{
    "ResourceAppId"  = $graphSp.AppId
    "ResourceAccess" = $permissionGrantList
}

#Create the Application Registration
Write-Host "Creating the application registration named '$appName'..."
$newApp = $null #Ensure $newApp is clear before the try block
try {
    $appParams = @{
        DisplayName            = $appName
        Web                    = @{ HomePageUrl = $homepageUrl }
        RequiredResourceAccess = @($requiredResourceAccess)
        Info                   = @{ MarketingUrl = $homepageUrl }
    }
    $newApp = New-MgApplication -BodyParameter $appParams

    Write-Host "Application '$($newApp.DisplayName)' created successfully!" -ForegroundColor Green
    Write-Host "Application (Client) ID: $($newApp.AppId)"
    Write-Host "Object ID: $($newApp.Id)"

}
catch {
    Write-Error "An error occurred during application creation. Error: $_"
    #Stop the script if the main app creation fails
    Disconnect-MgGraph
    return
}

#Set the Logo - Temp Downloads, as can't set via URL
Write-Host "Downloading and setting the logo..."
try {
    #Download the logo file locally
    Invoke-WebRequest -Uri $logoUrl -OutFile $tempLogoPath
    
    #Set the logo directly from the downloaded file
    Set-MgApplicationLogo -ApplicationId $newApp.Id -InFile $tempLogoPath
    
    Write-Host "Logo added successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to download or set the logo. Error: $_"
}
finally {
    #Clean up the temporary file regardless of success or failure
    if (Test-Path $tempLogoPath) {
        Remove-Item $tempLogoPath
    }
}

#Reminder and Disconnect
Write-Host "---"
Write-Host "IMPORTANT: Admin consent has been requested but NOT granted." -ForegroundColor Yellow
Write-Host "A Global or Application Administrator must grant consent in the Entra portal." -ForegroundColor Yellow

Disconnect-MgGraph