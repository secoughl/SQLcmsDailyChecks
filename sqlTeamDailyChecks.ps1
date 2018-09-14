#Pull in the needed
#[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") |Out-Null
try {
    import-module sqlps -DisableNameChecking    
}
catch {
    "Problem importing sqlps, please ensure it exists"
}


function Invoke-DailyCheck {
    [cmdletbinding()]
    param(
        [string] $Query, $outputFile, $scope, $format, $cms, $checkname
    )
    Clear-Content $outputFile
    $jobMessage = @()
    $jobSqlServers = invoke-sqlcmd -query $scope -ServerInstance $cms -ConnectionTimeout 10 | select server_name

    foreach ($jobSqlServer in $jobSqlServers.server_name) {

        try {
            $jobMessageTemp = invoke-sqlcmd -query $Query -ServerInstance $jobSqlServer -ConnectionTimeout 10 -erroraction silentlycontinue | Select-Object $format
            $jobMessage += $jobMessageTemp
        }
        catch {"couldn't connect to $jobSqlServer during $checkname"}

        finally {$jobMessage | Export-Csv $outputFile -NoTypeInformation -ErrorAction SilentlyContinue}
    }
}

function Get-InstanceDisks {
    [cmdletbinding()]
    param(
        [string]$scope, $cms, $outputFile, $format,
        [decimal]$cutoff
    )
    Clear-Content $outputFile
    $messageArray = @()
    $mountedServers = invoke-sqlcmd -query $scope -ServerInstance $cms -ConnectionTimeout 10 | select server_name
    Foreach ($mountedServer in $mountedServers.server_name) {

        if ((Test-Connection -Quiet $mountedServer.Split('\')[0]) -eq - $true) {
            Try {
                $Volumes = Get-WmiObject -ComputerName $mountedServer.Split('\')[0] win32_volume | Where-Object {$_.Capacity -gt 0}
            }
            catch {
                "Error grabbing Volumes from $mountedServer"
                Continue
            }
            $messageObj = "" | select $format
            Foreach ($Volume in $Volumes) {

                If ($Volume.Label -ne "System Reserved" -or $Volume.Label -ne "System") {
                    $FreeSpace = ([math]::round(($Volume.FreeSpace / 1073741824), 2))
                    $TotalSpace = ([math]::round(($Volume.Capacity / 1073741824), 2))
                    $UsedPercentage = 100 - (($FreeSpace / $TotalSpace) * 100)
                    $driveName = $Volume.Label -replace ' ', ''

                    $messageObj.Server_name = $mountedServer
                    $messageObj.UsedPercentage = $UsedPercentage
                    $messageObj.driveName = $driveName


                    If ($messageObj.UsedPercentage -gt $cutoff) {
                        $messageArray += $messageObj | Select-Object $format
                    }
                }
            }

            $messageArray | Sort-Object -Property UsedPercentage -Descending| Export-Csv $outputFile -NoTypeInformation -ErrorAction SilentlyContinue 
        }
    }

}

Function Send-DailyChecks {
    [cmdletbinding()]
    Param (
        [string] $reportDirectory, $sendTo, $SMTPRelay, $fromAddress
    )

    cd c:
    $anonUsername = "anonymous"
    $anonPassword = ConvertTo-SecureString "anonymous" -AsPlainText -Force
    $anonCredentials = New-Object System.Management.Automation.PSCredential($anonUsername, $anonPassword)
    $Subject = "SQL Daily Checks Completed, see attached"

    $Body = $bodyUpper +
    "<BR>" + "<b>Failed AG DBs:</b><BR>" + (import-csv -path $avgOutputFile| convertto-html -fragment) +
    "<BR>" + "<b>Jobs that failed their last run:</b><BR>" + (import-csv -path $jobOutputFile | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Disabled DBA Jobs:</b><BR>" + (import-csv -path $dbaJobOutputFile | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Disks over 80%:</b><BR>" + (import-csv -path $mountSpaceOutputFile | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Backups out of Retention:</b><BR>" + (import-csv -path $fullRetentionOutputFile | ConvertTo-Html -Fragment) +
    $bodyLower

    Send-MailMessage -From $fromAddress -to $SendTo -Subject $Subject -Bodyashtml $Body -SmtpServer $SMTPRelay -Credential $anonCredentials
}


#Query Variables
$allQuery = "select server_name from msdb.dbo.sysmanagement_shared_registered_servers 
    where server_group_id not in ('26','27','28') and server_name not like '%OFF%'"
$testQuery = "select server_name from msdb.dbo.sysmanagement_shared_registered_servers "+
    "where server_name like 'Server_Name_here'"
$avgQuery = "if exists (select name from sys.sysobjects where name = 'dm_hadr_availability_replica_states')
select rcs.replica_server_name
       , sag.name as avg_name
       , db_name(drs.database_id) as 'DB_Name'
       , rs.role_desc as 'Server_Role_Desc'
       , rs.connected_state_desc as 'Server_connected_state'
       , rs.synchronization_health_desc as 'server_sync_health'
       , drs.synchronization_state_desc as 'db_synch_sTate'
       , drs.synchronization_health_desc as 'db_sync_health'
       , mf.size/128 as sizemb

from
       sys.dm_hadr_availability_replica_states rs
join sys.dm_hadr_availability_replica_cluster_states rcs
       on rcs.replica_id = rs.replica_id
join sys.dm_hadr_database_replica_states drs
       on rs.replica_id = drs.replica_id
join sys.master_files mf on mf.database_id = drs.database_id and type_desc = 'ROWS'
join sys.availability_groups sag on sag.group_id = rs.group_id

where
drs.synchronization_health_desc not like 'HEALTHY'"
$jobQuery = ";WITH CTE_MostRecentJobRun AS  
 (  
 -- For each job get the most recent run (this will be the one where Rnk=1)  
 SELECT job_id,run_status,run_date,run_time  
 ,RANK() OVER (PARTITION BY job_id ORDER BY run_date DESC,run_time DESC) AS Rnk  
 FROM msdb.dbo.sysjobhistory  
 WHERE step_id=0  
 )  
SELECT   
  @@servername as Server_name
  ,name  AS [Job_Name]
,CONVERT(VARCHAR,DATEADD(S,(run_time/10000)*60*60 /* hours */  
  +((run_time - (run_time/10000) * 10000)/100) * 60 /* mins */  
  + (run_time - (run_time/100) * 100)  /* secs */,  
  CONVERT(DATETIME,RTRIM(run_date),113)),100) AS [Time_Run] 
 ,CASE WHEN enabled=1 THEN 'Enabled'  
     ELSE 'Disabled'  
  END [Job Status]
FROM     CTE_MostRecentJobRun MRJR  
JOIN     msdb.dbo.sysjobs SJ  
ON       MRJR.job_id=sj.job_id  
WHERE    Rnk=1  
AND name like 'DBA%'
AND      run_status=0 -- i.e. failed  
ORDER BY name  "
$dbaJobQuery = "select @@servername as [Server_Name], name as [Name], date_modified as [Date_Modified] 
from msdb.dbo.sysjobs where name like '%DBA%' and enabled <> 1"
$retentionQuery = "
IF OBJECT_ID('tempdb..#retention_checks') IS NOT NULL DROP TABLE #retention_checks

select d.name as DatabaseName, d.recovery_model_desc as RecoveryModel,
       getdate() as LastFULLBackupDate,
       0 as FULLBackup_DaysOld,
       getdate() as LastDIFFBackupDate,
       0 as DIFFBackup_DaysOld,
       getdate() as LastLOGBackupDate,
       0 as LOGBackup_MinutesOld
       into #retention_checks
from sys.databases d
where d.name <> 'tempdb'
and d.state_desc = 'ONLINE'
and sys.fn_hadr_backup_is_preferred_replica (d.name) = 1;


update #retention_checks set LastFullBackupDate = isnull((select MAX(backup_finish_date) from msdb..backupset where type = 'D' and #retention_checks.databasename = database_name ),'2000-01-01 00:00:00.001');
update #retention_checks set LastDIFFBackupDate = isnull((select MAX(backup_finish_date) from msdb..backupset where type = 'i' and #retention_checks.databasename = database_name ),'2000-01-01 00:00:00.001');
update #retention_checks set LastLOGBackupDate = isnull((select MAX(backup_finish_date) from msdb..backupset where type = 'l' and #retention_checks.databasename = database_name ),'2000-01-01 00:00:00.001');


update #retention_checks set FULLBackup_DaysOld = DATEDIFF(dd, LastFullBackupdate, GETDATE());
update #retention_checks set DIFFBackup_DaysOld = DATEDIFF(dd, LastDIFFBackupDate, GETDATE());
update #retention_checks set LogBackup_MinutesOld = DATEDIFF(mi, LastLOGBackupDate, GETDATE());

select @@servername as server_name,* from #retention_checks 
where ( (FULLBackup_DaysOld > 7) OR (DIFFBackup_DaysOld > 2 and databasename not like 'master') OR (LogBackup_MinutesOld > 100 and RecoveryModel like 'FULL') )
order by DatabaseName;
"


#Formatting variables for CSV output (which are then read back in for emailing)
$avgFormat = 'replica_server_name', 'avg_name', 'db_name', 'db_sync_health'
$failedJobFormat = 'Server_name', 'Job_name', 'Time_Run'
$dbaJobFormat = 'Server_Name', 'Name', 'Date_Modified'
$diskFormat = 'Server_Name', 'UsedPercentage', 'DriveName'
$fullRetentionFormat = 'Server_Name', 'DatabaseName', 'FullBackup_DaysOld', 'DiffBackup_DaysOld', 'LogBackup_MinutesOld'

cd c:

#Path Variables
$reportPath = "\\netapp.domain.mil\backupshare$\Automation\"
$avgOutputFile = $reportPath + "agDailyReport.txt"
$mountSpaceOutputFile = $reportPath + "diskReporting.txt"
$jobOutputFile = $reportPath + "jobFails.txt"
$dbaJobOutputFile = $reportPath + "dbaJobFails.txt" 
$fullRetentionOutputFile = $reportPath + "fullRetention.txt"
$bodyUpper = Get-Content $reportPath"bodyUpper.txt" -raw
$bodyLower = Get-Content $reportPath"bodyLower.txt" -raw

$smtp = "smtp-relay.domain.mil"
$sendToAll = "<Database_Distro@domain.mil>"
$sendFrom = "SQL Daily Checks <dailychecks@domain.mil>"
$cms = 'CMSServerName'


Invoke-DailyCheck -scope $allQuery -cms $cms -Query $avgQuery -outputFile $avgOutputFile -checkname 'AG Check' -format $avgFormat 
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $jobQuery -outputFile $jobOutputFile -checkname 'Failed Job Check' -format $failedJobFormat
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $dbaJobQuery -outputFile $dbaJobOutputFile -checkname 'Disabled Job Check' -format $dbaJobFormat
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $retentionQuery -outputFile $fullRetentionOutputFile -checkname 'Retention Check' -format $fullRetentionFormat
Get-InstanceDisks -scope $allQuery -cms $cms -outputFile $mountSpaceOutputFile -cutoff 80 -format $diskFormat 

Send-DailyChecks -sendTo $sendToAll -fromAddress $sendFrom -SMTPRelay $smtp


