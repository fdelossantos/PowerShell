# Loop through the server list
Get-Content "directorios.txt" | %{
 
    # Define what each job does
    $ScriptBlock = {
      param($pipelinePassIn) 
      Migrate-NASwithNTFSpermissions.ps1 -FolderBase $pipelinePassIn -OldDomain DOMAIN1 -NewDomain DOMAIN2 -TermDictionary .\migratentfstranslations.json
    }
   
    # Execute the jobs in parallel
    Start-Job $ScriptBlock -ArgumentList $_
  }
   
  Get-Job
   
  # Wait for it all to complete
  While (Get-Job -State "Running")
  {
    Start-Sleep -Seconds 30
  }
   
  # Getting the information back from the jobs
  Get-Job | Receive-Job