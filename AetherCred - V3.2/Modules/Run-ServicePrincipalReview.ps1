function Get-AetherCredServicePrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GraphAccessToken
    )

    begin {
        Write-Verbose "Starting internal function Get-AetherCredServicePrincipal."
        $headers = @{
            "Authorization" = "Bearer $GraphAccessToken"
            "Content-Type"  = "application/json"
        }
    }

    process {
        try {
            $allApplications = @()
            $applicationsUri = "https://graph.microsoft.com/v1.0/applications"
            while ($applicationsUri) {
                Write-Verbose "Querying for applications from: $applicationsUri"
                $applicationsResponse = Invoke-RestMethod -Uri $applicationsUri -Headers $headers -Method Get
                $allApplications += $applicationsResponse.value
                $applicationsUri = $applicationsResponse.'@odata.nextLink'
            }
            
            $allServicePrincipals = @()
            $servicePrincipalsUri = "https://graph.microsoft.com/v1.0/servicePrincipals"
            while ($servicePrincipalsUri) {
                Write-Verbose "Querying for service principals from: $servicePrincipalsUri"
                $servicePrincipalsResponse = Invoke-RestMethod -Uri $servicePrincipalsUri -Headers $headers -Method Get
                $allServicePrincipals += $servicePrincipalsResponse.value
                $servicePrincipalsUri = $servicePrincipalsResponse.'@odata.nextLink'
            }

            Write-Host "Found $($allApplications.Count) applications and $($allServicePrincipals.Count) service principals."

            $report = foreach ($sp in $allServicePrincipals) {
                Write-Verbose "Processing Service Principal: $($sp.displayName)"
                $app = $allApplications | Where-Object { $_.appId -eq $sp.appId }

                #Get OAuth2 permission grants for the service principal
                $oauthGrantsUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/oauth2PermissionGrants"
                $oauthGrants = try {
                    (Invoke-RestMethod -Uri $oauthGrantsUri -Headers $headers -Method Get -ErrorAction Stop).value
                } catch {
                    Write-Warning "Could not retrieve OAuth2 grants for SPN '$($sp.displayName)' (ID: $($sp.id)). Error: $($_.Exception.Message)"
                    @() #Return empty array on error
                }

                #Get App Role Assignments for the service principal
                $appRoleAssignmentsUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignments"
                $appRoleAssignments = try {
                    (Invoke-RestMethod -Uri $appRoleAssignmentsUri -Headers $headers -Method Get -ErrorAction Stop).value
                } catch {
                     Write-Warning "Could not retrieve App Role Assignments for SPN '$($sp.displayName)' (ID: $($sp.id)). Error: $($_.Exception.Message)"
                    @() #Return empty array on error
                }

                #Construct the final object for the report
                [PSCustomObject]@{
                    DisplayName        = $sp.displayName
                    ServicePrincipalId = $sp.id
                    AppId              = $sp.appId
                    ApplicationId      = if ($app) { $app.id } else { "N/A" }
                    CreatedDateTime    = if ($app) { $app.createdDateTime } else { $null }
                    SignInAudience     = if ($app) { $app.signInAudience } else { "N/A" }
                    PublisherDomain    = $sp.publisherName
                    Tags               = -join ($sp.tags | ForEach-Object { "$_;" })
                    Notes              = $sp.notes
                    ServicePrincipalType = $sp.servicePrincipalType
                    OAuth2Permissions  = $oauthGrants | Select-Object -ExpandProperty scope -ErrorAction SilentlyContinue
                    AppRoleAssignments = $appRoleAssignments | Select-Object -ExpandProperty appRoleId -ErrorAction SilentlyContinue
                }
            }

            Write-Output $report

        }
        catch {
            Write-Error "An error occurred during API call in Get-AetherCredServicePrincipal: $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "Finished Application and Service Principal analysis."
    }
}

# ==============================================================================
# Invoke-ServicePrincipalReview Section
# ==============================================================================
function Invoke-ServicePrincipalReview {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    Write-Host "Initiating Service Principal Review..." -ForegroundColor Cyan

    try {
        Write-Host "Requesting new access token for Service Principal API calls..." -ForegroundColor Yellow
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

        $reportData = Get-AetherCredServicePrincipal -GraphAccessToken $accessToken
        
        Write-Host "Service Principal Review completed successfully." -ForegroundColor Green
        return $reportData
    }
    catch {
        Write-Error "Failed to execute Service Principal Review. Error: $($_.Exception.Message)"
        return $null
    }
}
