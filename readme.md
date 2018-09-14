Setup:
1. Deploy all files to a network or local location that the Account performing the checks can access.
2. Update SQLDailyChecks.ps1 in the following manner to fit your environment:
- Line 93 - $allQuery - Update this for whatever you want to filter off of the results from CMS. Currently shows example Server Group exemptions and wildcard name exemptions ('%OFF%')
- Line 95 - $testQuery - Update this to something simple (like grabbing a single specific instance) and pass it as your scope for rapid testing
- Line 141 - Failed job query - 'name like 'DBA%' - This line exists because, at this customer, all of the jobs we care about across the enterprise start with the name DBA. Please update or remove this line to conform to your environment
- Line 145 - Disabled job query - 'name like 'DBA%' - This line exists because, at this customer, all of the jobs we care about across the enterprise start with the name DBA. Please update or remove this line to conform to your environment
- Line 173 - Please set your retention numbers here based on your backup cadence. We perform a Full every week, a diff every day, and TLOGs every 30 minutes, so we alert on Fulls > 7 days, Diffs > 2 Days, and TLOGs > 100 minutes
- Line 188 - $reportPath - update this to the base directory that holds all of your output files, as well as the upper and lower blocks of HTML for your email template. We use a shared network location for ease of updating and consolidation.  Please ensure there is a trailing \
- Line 188 through 195 - Update these filenames if you change them from the example, these need to be accurate as they control both where the checks are written and what imports occur to generate the HTML email
- Line *198 through 201* - Update your smtprelay, address to send to, address to send from, and finally CMS server name

In order for the disk percentage check to run, whatever account is used will need rights to remote-wmi on the servers that host your instances.


Script use:

Invoke-DailyCheck -scope $allQuery -cms $cms -Query $avgQuery -outputFile $avgOutputFile -checkname 'AG Check' -format $avgFormat 
-scope: query to submit to CMS to build your list of servers
-cms: your CMS server
-Query: what check you want to run
-outputFile: where to write the results of the check
-checkname: Not entirely required, just useful for human-readable errors 
-format: used in the export-csv and import-csv to keep everything clean

Should you want to use this function to roll in your own checks:

All you need is a string that contains the SQL query you want to run, a list of the columns that you want to retain, and a file to write to. Once you have updated the script with those values, edit the function 'Send-DailyChecks' to include the additional import line.

Get-InstanceDisks -scope $allQuery -cms $cms -outputFile $mountSpaceOutputFile -cutoff 80 -format $diskFormat 
-scope: query to submit to CMS to build your list of servers
-cms: your CMS server
-outputFile: where to write the results of the check
-cutoff: what percent used to start including in the email
-format: used in the export-csv and import-csv to keep everything clean

Scheduling:
We currently schedule using a SQL Agent Job which runs daily. In order to ensure maximum compatibility in our secured environment, we copy the script down from the network, call PowerShell using our local copy, then at finish delete the local copy. A copy of this job is included below.

Example SQL Agent Job:
USE [msdb]
GO

/****** Object:  Job [DBA - Checks - Daily]    Script Date: 9/7/2018 8:45:32 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 9/7/2018 8:45:32 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - Checks - Daily', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Daily_Check_Script]    Script Date: 9/7/2018 8:45:33 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Daily_Check_Script', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'copy \\netapp.domain.mil\Automation\sqlTeamDailyChecks.ps1 c:\temp\sqlTeamDailyChecks.ps1 /y && C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe c:\temp\sqlTeamDailyChecks.ps1 && del /f c:\temp\sqlTeamDailyChecks.ps1', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'DailyRun', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=62, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20160401, 
		@active_end_date=99991231, 
		@active_start_time=50000, 
		@active_end_time=235959, 
		@schedule_uid=N'aa18f627-5a92-48c8-8f88-d7b97ec5a747'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


