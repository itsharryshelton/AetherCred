function Invoke-GroupReview {

    try {
        Write-Host "`nInitiating full Group Review for the tenant..." -ForegroundColor Green
        Write-Host "This may take a significant amount of time depending on the number of groups." -ForegroundColor Yellow

        #Get all groups in the tenant
        $allGroups = Get-MgGroup -All -ErrorAction Stop
        if (-not $allGroups) {
            Write-Warning "No groups were found in the tenant."
            return $null
        }

        $reportData = [System.Collections.Generic.List[psobject]]::new()
        $totalGroups = $allGroups.Count
        $processedCount = 0
        $reportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        #Loop through each group to gather details
        foreach ($group in $allGroups) {
            $processedCount++
            Write-Progress -Activity "Processing Group Review" -Status "Processing group $($group.DisplayName) ($processedCount of $totalGroups)" -PercentComplete (($processedCount / $totalGroups) * 100)

            $groupId = $group.Id

            #Get Owners Section
            $ownerNames = try {
                (Get-MgGroupOwner -GroupId $groupId -ErrorAction Stop | Select-Object -ExpandProperty AdditionalProperties).userPrincipalName
            }
            catch {
                Write-Warning "Could not retrieve owners for group '$($group.DisplayName)' (ID: $groupId)."
                @("Error retrieving owners")
            }
            if (-not $ownerNames) { $ownerNames = @("No owners found") }

            #Get Members Section
            $memberNames = try {
                (Get-MgGroupMember -GroupId $groupId -All -ErrorAction Stop | Select-Object -ExpandProperty AdditionalProperties).userPrincipalName
            }
            catch {
                Write-Warning "Could not retrieve members for group '$($group.DisplayName)' (ID: $groupId)."
                @("Error retrieving members")
            }
            if (-not $memberNames) { $memberNames = @("No members found") }


            # Determine group type
            $groupType = "Security" # Default to Security
            if ($group.GroupTypes -contains "Unified") { $groupType = "Microsoft 365" }
            if ($group.MailEnabled -eq $false) { $groupType += " (Mail-Disabled)"}
            if ($group.SecurityEnabled -eq $false) { $groupType = "Distribution List"}


            #Create PSCustomObject for the report
            $outputObject = [PSCustomObject]@{
                "GroupName"         = $group.DisplayName
                "GroupType"         = $groupType
                "EmailAddress"      = $group.Mail
                "Description"       = $group.Description
                "ObjectID"          = $groupId
                "GroupOwners"       = $ownerNames
                "GroupMembers"      = $memberNames
                "MemberCount"       = $memberNames.Count
                "ReportDate"        = $reportTimestamp
            }
            
            $reportData.Add($outputObject)

            #Add a small delay to help prevent Graph API throttling on large tenants - this might need adjusting if you find the throttle either breaks or too slow depending on tenant size...
            Start-Sleep -Milliseconds 200
        }

        Write-Progress -Activity "Processing Group Review" -Completed
        Write-Host "`nGroup review complete. Processed $totalGroups groups." -ForegroundColor Green
        
        return $reportData
    }
    catch {
        Write-Error "An error occurred during the group review: $($_.Exception.Message)"
        return $null
    }
}
