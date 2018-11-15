# -----------------------------------------------------------------------------
# Author:      Sean Coughlin, Microsoft
# Date:        Sep 2018
#
# History:
# Date         Name                     Comment
# -----------  -----------------------  ----------------------------------------
# 14 Sep 2018  Sean Coughlin (MSFT)     Created
# 14 Sep 2018  Chad Churchwell (MSFT)   Initial TSQL Scripting
# 18 Sep 2018  Sean Coughlin (MSFT) / Patrick Keisler (MSFT)     Disk Percentage handled by TSQL
# 18 Sep 2018  Sean Coughlin (MSFT)     Get-Error Implimented, HTML Report Generation handled
# 9 Nov 2018  Sean Coughlin (MSFT)      Failures now included in E-mail with link to errorlog
# File Name:   SQLcmsDailyChecks.ps1
#
# Purpose:     PowerShell script to automate morning health checks.
#
# -----------------------------------------------------------------------------
#
# Copyright (C) 2018 Microsoft Corporation
#
# Disclaimer:
#   This is SAMPLE code that is NOT production ready. It is the sole intention of this code to provide a proof of concept as a
#   learning tool for Microsoft Customers. Microsoft does not provide warranty for or guarantee any portion of this code
#   and is NOT responsible for any affects it may have on any system it is executed on  or environment it resides within.
#   Please use this code at your own discretion!
# Additional legalese:
#   This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.
#   THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
#   INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#   We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute
#   the object code form of the Sample Code, provided that You agree:
#       (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded;
#      (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and
#     (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys' fees,
#           that arise or result from the use or distribution of the Sample Code.
# -----------------------------------------------------------------------------



try {
    import-module sqlps -DisableNameChecking    
}
catch {
    "Problem importing sqlps, please install it from aka.ms/sqlps"
}


function Invoke-DailyCheck {
    [cmdletbinding()]
    param(
        [string] $Query, $outputFile, $scope, $format, $cms, $checkname
    )
    if (test-path $outputFile) {
        Clear-Content $outputFile
    }
    $jobMessage = @()
    $jobSqlServers = invoke-sqlcmd -query $scope -ServerInstance $cms -ConnectionTimeout 10 | Select-Object server_name

    foreach ($jobSqlServer in $jobSqlServers.server_name) {

        try {
            $jobMessageTemp = invoke-sqlcmd -query $Query -ServerInstance $jobSqlServer -ConnectionTimeout 10 -erroraction silentlycontinue | Select-Object $format
            $jobMessage += $jobMessageTemp
        }
        catch {
            $friendlyError = "couldn't connect to $jobSqlServer during $checkname"
            $friendlyError
            Add-ErrorItem -reportDirectory $reportPath -cleanError $friendlyError -fullError $_.Exception
        }

        finally {$jobMessage | Export-Csv $outputFile -NoTypeInformation -ErrorAction SilentlyContinue}
    }
}# Invoke-DailyCheck
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

    If ($Null -ne (Get-Content -Path $notificationOutputFile)) {
        Add-Content -Path $notificationOutputFile "<b>Please check $errorLog for details</b><BR>"
        }

    $Body = $bodyUpper +
    "<BR>" + "<b>Failed AG DBs:</b><BR>" + (import-csv -path $agOutputFile| convertto-html -fragment) +
    "<BR>" + "<b>Jobs that failed their last run:</b><BR>" + (import-csv -path $jobOutputFile | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Disabled DBA Jobs:</b><BR>" + (import-csv -path $dbaJobOutputFile | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Disks over 80%:</b><BR>" + (import-csv -path $mountSpaceOutputFile | sort-object used_space_pct -descending | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Backups out of Retention:</b><BR>" + (import-csv -path $fullRetentionOutputFile | ConvertTo-Html -Fragment) +
    "<BR>" + "<b>Failed Checks:</b><BR>" + (Get-Content -Path $notificationOutputFile) +
    $bodyLower

    $Body | out-file $reportPath"Daily_Report.html"
    
    try {
        # -UseSsl is a supported flag if required
        # If your SMTP Relay requires actual authentication, feed it into the $anonUsername and $anonPassword variables and it will be built into a credential automatically
        Send-MailMessage -From $fromAddress -to $SendTo -Subject $Subject -Bodyashtml $Body -SmtpServer $SMTPRelay -Credential $anonCredentials -ErrorAction Stop
    }
    catch {
        $friendlyError = "Message Send failed to $SMTPRelay"
        $friendlyError
        Add-ErrorItem -reportDirectory $reportPath -cleanError $friendlyError -fullError $_.Exception
    }
    
}# Send-DailyChecks
Function Add-ErrorItem {
    [cmdletbinding()]
    Param (
        [string] $reportDirectory, $cleanError, $fullError
    )
    $timeStamp = get-date -format g
    $dirtyOutput = "$cleanError", "$timeStamp", "$fullError"
    $cleanOutput = $dirtyOutput | Out-String
    $notificationOutput = "$cleanError"+"<BR>" 

    $cleanOutPut | Add-Content $errorLog
    $notificationOutput | Add-Content $notificationOutputFile
    
}# Add-ErrorItem

cd c:

#Path and pertinent Variables
$reportPath = "\\networkshare\sharepath\dailyReturns\"
$agOutputFile = $reportPath + "reports\agDailyReport.txt"
$mountSpaceOutputFile = $reportPath + "reports\diskReporting.txt"
$jobOutputFile = $reportPath + "reports\jobFails.txt"
$dbaJobOutputFile = $reportPath + "reports\dbaJobFails.txt" 
$fullRetentionOutputFile = $reportPath + "reports\fullRetention.txt"
$notificationOutputFile = $reportPath + "reports\notificationOutput.txt"
$errorLog = $reportPath + "errorlog.txt"
$bodyUpper = Get-Content $reportPath"html\bodyUpper.html" -raw
$bodyLower = Get-Content $reportPath"html\bodyLower.html" -raw

$smtp = "smtp-relay.domain.com"
$sendToAll = "<DataCenter_Database_Distro@domain.com>"
$sendToTest = "Sean Coughlin <sean.coughlin@domain.com>"
$sendFrom = "SQL Daily Checks <dailycheck@domain.com>"
$cms = 'CMSSQLSERVER'
$diskCutOff = 80


#Formatting variables for CSV output (which are then read back in for emailing)
$agFormat = 'replica_server_name', 'avg_name', 'db_name', 'db_sync_health'
$failedJobFormat = 'Server_name', 'Job_name', 'Time_Run'
$dbaJobFormat = 'Server_Name', 'Name', 'Date_Modified'
$diskFormat = 'Server_Name', 'UsedPercentage', 'DriveName'
$fullRetentionFormat = 'Server_Name', 'DatabaseName', 'FullBackup_DaysOld', 'DiffBackup_DaysOld', 'LogBackup_MinutesOld'
$diskTSQLFormat = 'Server_Name', 'used_space_pct', 'volume_mount_point', 'total_gb', 'available_gb'

#Query Variables
$allQuery = "select server_name from msdb.dbo.sysmanagement_shared_registered_servers 
            where server_name not like '%OFF'"
$testQuery = "select server_name from msdb.dbo.sysmanagement_shared_registered_servers 
             where server_name like 'Server_Name_here'"
$agQuery = "if exists (select name from sys.sysobjects where name = 'dm_hadr_availability_replica_states')
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
$failedJobQuery = ";WITH CTE_MostRecentJobRun AS  
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
            --AND name like 'DBA%'
            AND      run_status=0 -- i.e. failed  
            ORDER BY name  "
$dbaDisabledJobQuery = "select @@servername as [Server_Name], name as [Name], date_modified as [Date_Modified] 
                --from msdb.dbo.sysjobs where name like '%DBA%' and enabled <> 1
                from msdb.dbo.sysjobs where enabled <> 1"
$retentionQuery = "IF OBJECT_ID('tempdb..#retention_checks') IS NOT NULL DROP TABLE #retention_checks

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
                --enable if 2014+ to only care about primary replicas
		        --and (sys.fn_hadr_is_primary_replica (d.name) = 1 or sys.fn_hadr_is_primary_replica (d.name) is null);
                

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
$diskTSQL = "SELECT DISTINCT 

        @@SERVERNAME as [server_name]
		,100-CONVERT(DECIMAL(18,2), vs.available_bytes * 1. / vs.total_bytes * 100.) AS used_space_pct
		,vs.volume_mount_point
		,vs.logical_volume_name
		,CONVERT(DECIMAL(18,2), vs.total_bytes/1073741824.0) AS total_gb
		,CONVERT(DECIMAL(18,2), vs.available_bytes/1073741824.0) AS available_gb
		       

    FROM sys.master_files AS f WITH (NOLOCK)
	CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs 
	where 100-(CONVERT(DECIMAL(18,2), vs.available_bytes * 1. / vs.total_bytes * 100.)) > $diskCutOff
	ORDER BY vs.volume_mount_point OPTION (RECOMPILE);"
#
if (test-path $notificationOutputFile) {
        Clear-Content $notificationOutputFile
}

Invoke-DailyCheck -scope $allQuery -cms $cms -Query $agQuery -outputFile $agOutputFile -checkname 'AG Check' -format $agFormat 
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $failedJobQuery -outputFile $jobOutputFile -checkname 'Failed Job Check' -format $failedJobFormat
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $dbaDisabledJobQuery -outputFile $dbaJobOutputFile -checkname 'Disabled Job Check' -format $dbaJobFormat
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $retentionQuery -outputFile $fullRetentionOutputFile -checkname 'Retention Check' -format $fullRetentionFormat
Invoke-DailyCheck -scope $allQuery -cms $cms -Query $diskTSQL -outputFile $mountSpaceOutputFile -checkname 'Disk Check' -format $diskTSQLFormat
#>

Send-DailyChecks -sendTo $sendToAll -fromAddress $sendFrom -SMTPRelay $smtp


