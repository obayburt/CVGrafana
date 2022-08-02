$params = @{
  "username"="username";
  "password"="password"
}
$headers = @{
    "Accept" = "application/json"
    "Content-type" = "application/json"

}
#job types and status set
$body = '{
    "jobFilter": {    
        "statusList": [
			"Running"
		],
        "jobTypeList": [
            144,4,14
        ]
    }
}'

while($true){
$row = @()
$joblist = Invoke-RestMethod -Uri http://<CommserveWS>/webconsole/api/Jobs -Method Post  -Headers $headers -Body ($body )-ErrorAction SilentlyContinue -ErrorVariable ups
if($ups)
{
    $authorization = Invoke-RestMethod -Uri http://<CommserveWS>/webconsole/api/Login -Method Post -Body ($params|ConvertTo-Json)  -Headers $headers
    $headers.Authtoken = $authorization.token
    $ups = $false

}
$jobs = $joblist.jobs.jobSummary.jobId
if($jobs -eq $null)
{
    echo "no active jobs"
    sleep -Seconds 300
    continue
}
        foreach($j in $jobs){

                $jobdetails = Invoke-RestMethod -Uri http://<CommserveWS>/webconsole/api/JobDetails -Method Post  -Headers $headers -Body (@{"jobId" = $j}|ConvertTo-Json)
                $obj = New-Object -TypeName psobject
                $obj | Add-Member -MemberType NoteProperty -Name "JobId" -Value $j
                $throughput= Invoke-Sqlcmd -ServerInstance "<CommserveDBIP>" -Database "CommServ" -Query "Select CurrentThroughput from jmbkpjobinfo WITH(NOLOCK) where jobid= $j"      
                $obj | Add-Member -MemberType NoteProperty -Name "throughput" -Value ([int]$throughput.CurrentThroughput)
                    $jobdetails.job.jobDetail.generalInfo.subclient.psobject.Properties | %{
                    $obj | Add-Member -MemberType NoteProperty -Name $_.Name -Value $_.Value


                        }
               $pol = $jobdetails.job.jobDetail.generalInfo.storagePolicy
               $copy = Invoke-RestMethod -Uri "http://<CommserveWS>/webconsole/api/V2/StoragePolicy/$($pol.storagePolicyId)?propertyLevel=10" -Method Get -Headers $headers
               $lib = $copy.policies.copies | where {$_.isDefault -eq 1} | %{$_.library.libraryName}
               $obj | Add-Member -MemberType NoteProperty -Name "StoragePolicy" -Value $pol.storagePolicyName
               $obj | Add-Member -MemberType NoteProperty -Name "Library" -Value $lib
               $obj | Add-Member -MemberType NoteProperty -Name "Date" -Value (Get-Date -Second 00  -Millisecond 0 -Format "o")
               $row += $obj
        }
        #set index name for each day
        $indexname = ((Get-Date).AddHours(-3) | Get-Date -Format "ddMMyyyy") + "data" #set to GMT zone
        #send data one line at a time as ndjson
        foreach($l in $row){
        Invoke-RestMethod -Uri https://localhost:9200/$($indexname)/_doc  -Headers $(@{"Authorization" = "<Auth Token>"}) -ContentType "application/json" -Body ($l | ConvertTo-Json) -Method Post | Out-Null
        }
        #wait for next minute
        $next =[datetime](get-date -Format HH:mm)
        $next = $next.AddMinutes(1)
        $current = [datetime](get-date -Format HH:mm:ss)
        sleep -seconds(New-TimeSpan -Start $current -End $next).TotalSeconds 
}

