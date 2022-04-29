<#
  .SYNOPSIS
  Exports the current set of Conditional Access policies to an Azure storage account.

  .DESCRIPTION
  Exports the current set of Conditional Access policies to an Azure storage account.

  .PARAMETER ContainerName
  Will be autogenerated if left empty

  .NOTES
  Permissions
   MS Graph (API): 
   - Policy.Read.All
   Azure IaaS: Access to the given Azure Storage Account / Resource Group

  .INPUTS
  RunbookCustomization: {
        "Parameters": {
            "CallerName": {
                "Hide": true
            }
        }
    }

#>

#Requires -Modules @{ModuleName = "RealmJoin.RunbookHelper"; ModuleVersion = "0.6.0" }

param(

    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "SenderMail" } )]
    [string] $From,
    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "SenderMail" } )]
    [string] $To,
    # CallerName is tracked purely for auditing purposes
    [Parameter(Mandatory = $true)]
    [string] $CallerName
)

Connect-RjRbGraph
<#$Body = "Hi Team,
Please find the list of Conditional Access Policies that are created or modified in the last 24 hours.

Thanks,
O365 Automation
Note: This is an auto generated email, please do not reply to this.
"#>
[array] $Modifiedpolicies = @()
$Currentdate = (Get-Date).AddDays(-1)
$AllPolicies = Invoke-RjRbRestMethodGraph -Resource "/policies/conditionalAccessPolicies"
foreach ($Policy in $AllPolicies)
{
	$policyModifieddate =  $Policy.modifiedDateTime
	$policyCreationdate = $Policy.createdDateTime 
	if (($policyModifieddate -gt $Currentdate) -or ($policyCreationdate -gt $Currentdate))
	{
		write-host "------There are policies updated in the last 24 hours, please refer txt file." -ForegroundColor Green
		IF (($policyModifieddate))
		{
			$Modifiedpolicies += "PolicyID:$($policy.ID) & Name:$($policy.DisplayName) & Modified date:$policyModifieddate" 
		}
		else
		{
			$Modifiedpolicies += "PolicyID:$($policy.ID) & Name:$($policy.DisplayName) & Creation date:$policyCreationdate" 
		}
	}
}

#send email if any changes to the Conditional Access Policies in the last 24 hours
If ($Null -ne ($Modifiedpolicies))
{
	write-host "Found policies" -ForegroundColor Yellow
    Write-Output $Modifiedpolicies
	#Send-MailMessage -From $From -To $To -Subject $Subject -Body $Body -Attachments (File-out "$Modifiedpolicies")
}