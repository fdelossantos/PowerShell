$usuarios | foreach {
Get-EXOMailbox -Identity $_.EmailAddress -PropertySets Minimum 
        | ForEach-Object { 
            $mbx = $_;
            $st = Get-EXOMailboxStatistics -Identity $mbx.UserPrincipalName; 
            if ($st.TotalItemSize.Value.ToBytes() -gt 50GB) 
            { [pscustomobject]@{ 
                    UserPrincipalName=$mbx.UserPrincipalName; 
                    DisplayName=$mbx.DisplayName; 
                    TotalItemSize=$st.TotalItemSize 
                } 
            } 
        }
}
$usuarios | foreach {
Get-MgUserTransitiveMemberOf -UserId $_.EmailAddress -All |
        Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' } |
        ForEach-Object {
            [pscustomobject]@{
                EmailAddress      = $email
                GroupDisplayName  = $_.AdditionalProperties.displayName
                GroupId           = $_.Id
                Note              = $null
            }
        }
    }


$usuarios | foreach { Get-MigrationUser -EmailAddress $_ } | 
    where {$_.BatchId -eq "Batch106 - CL 6-16"} |
    foreach  {
        New-MgGroupMember -GroupId "<GroupID>" -DirectoryObjectId (Get-MgUser -UserId $_.MailboxEmailAddress).Id -ErrorAction SilentlyContinue
}

$usuarios | foreach { Get-MigrationUser -EmailAddress $_ } | 
    where {$_.BatchId -eq "Batch107 - CL 2-6"} |
    foreach  {
        New-MgGroupMember -GroupId "<GroupID>" -DirectoryObjectId (Get-MgUser -UserId $_.MailboxEmailAddress).Id -ErrorAction SilentlyContinue
}

$usuarios | foreach { Get-MigrationUser -EmailAddress $_ } | 
    where {$_.BatchId -eq "Batch108 - CL 0-2"} |
    foreach  {
        New-MgGroupMember -GroupId "<GroupID>" -DirectoryObjectId (Get-MgUser -UserId $_.MailboxEmailAddress).Id -ErrorAction SilentlyContinue
}
