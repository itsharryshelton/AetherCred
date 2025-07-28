function Invoke-ConditionalAccessReview {
    Write-Host "Fetching all Conditional Access policies..."
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All
    }
    catch {
        Write-Error "Failed to retrieve Conditional Access policies. This typically requires a 'Global Reader' role or higher. Error: $_"
        return $null
    }

    if ($null -eq $policies -or $policies.Count -eq 0) {
        Write-Warning "No Conditional Access policies were found."
        # Return a placeholder object inside an array so the table has something to display.
        return @([PSCustomObject]@{
            PolicyName      = "No Conditional Access policies found"
            State           = "N/A"
            UsersAndGroups  = "N/A"
            IncludedApps    = "N/A"
            GrantControls   = "N/A"
            SessionControls = "N/A"
        })
    }

    $caData = @()
    foreach ($policy in $policies) {
        # Process Users/Groups assignments
        $assignments = @()
        if ($policy.Conditions.Users.IncludeUsers -contains "All") {
            $assignments += "All Users"
        } else {
            # In a real-world scenario, you might resolve these GUIDs to names
            $assignments += $policy.Conditions.Users.IncludeUsers
        }
        if ($policy.Conditions.Users.IncludeGroups) {
            $assignments += $policy.Conditions.Users.IncludeGroups | ForEach-Object { "Group:$($_)" }
        }

        # Process Included Apps
        $includedApps = @()
        if ($policy.Conditions.Applications.IncludeApplications -contains "All") {
            $includedApps += "All cloud apps"
        } else {
            $includedApps += $policy.Conditions.Applications.IncludeApplications
        }

        # Process Grant Controls
        $grantControls = $policy.GrantControls.Operator
        if ($policy.GrantControls.BuiltInControls) {
            $controls = $policy.GrantControls.BuiltInControls -join ', '
            # Replace 'mfa' with a more user-friendly 'Require MFA'
            $controls = $controls -replace 'mfa', 'Require MFA'
            $grantControls += " ($controls)"
        }

        $caData += [PSCustomObject]@{
            PolicyName      = $policy.DisplayName
            State           = $policy.State
            UsersAndGroups  = ($assignments -join ", ")
            IncludedApps    = ($includedApps -join ", ")
            GrantControls   = $grantControls
            SessionControls = if ($policy.SessionControls) { $policy.SessionControls.ApplicationEnforcedRestrictions.IsEnabled } else { $false }
        }
    }

    Write-Host "Successfully processed $($policies.Count) Conditional Access policies." -ForegroundColor Green
    return $caData
}
