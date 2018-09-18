## Setup<br>

**1. Deploy all files to a network or local location that the Account performing the checks can access.<br>
2. Update SQLDailyChecks.ps1 (Lines 121-221) in the following manner to fit your environment:**<br>

| Variable | Description |
| ----- | ----- |
| $reportPath | Root directory for reports and HTML files, please ensure it ends with \ |
| $agOutputFile | File to write results from Availability Group Check |
| $mountSpaceOutputFile | File to write results from Disk Check |
| $jobOutputFile | File to write results from Last Failed Jobs Check |
| $dbaJobOutputFile | File to write results from Disabled DBA Jobs Check |
| $fullRetentionOutputFile | File to write results from Backup Retention Check |
| $bodyUpper | First half of HTML template |
| $bodyLower | Second half of HTML Template |

**3. Update SQLDailyChecks.ps1 (Lines 131-136) in the following manner to fit your environment:**<br>

| Variable | Description |
| ----- | ----- |
| $smtp | Your SMTP Relay |
| $sendToAll | The Distribution Group you would like the Daily email to be sent to |
| $sendToTest | A single DBA's email should you need for testing purposes |
| $sendFrom | Email address the reports should come from |
| $cms | The server\instance name of your Central Management Server |
| $diskCutOff | When to start showing disk resultes in the e-mail |

**4. _Optional_ Update SQLDailyChecks.ps1 (Lines 139-222) to modify the baked-in check queries:**<br>

| Query Variable | Suggestion |
| ---- | ---- |
| $allQuery | Use the predicate to filter out Group / Server registrations you don't want included in your checks |
| $testQuery | Including for quick troubleshooting |
| $agQuery | Query to find any Availability Group database that doesn't have a status of 'Healthy' |
| $failedJobQuery | Finds all jobs that failed their last run. Consider a where clause based on name / state for your environment |
| $dbaDisabledJobQuery | Finds all jobs that are disabled (i.e. someone disabled a backup job and forgot about it.) Consider a where clause depending on your environment |
| $retentionQuery | Finds databases that have a most recent bacup that is out of your rentention window. Modify the where clause for your retention in days |
| $diskTSQL | Update $diskCutOff to ensure you get notified when drives being to reach percentage utilization that meets your threshold. |

## Script use:

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
We currently schedule using a SQL Agent Job which runs daily. In order to ensure maximum compatibility in our secured environment, we copy the script down from the network, call PowerShell using our local copy, then at finish delete the local copy. A copy of this job is included in the repo


## Updates:
**9/18/2018** disks percentage is now handled via TSQL, it is no different than any other use of Invoke-DailyCheck. The legacy (remoteWMI) version will be kept in the code for legacy purposes<br>
**9/18/2018** errors now result in a call to Get-Error which timestamps them and dumps them to a text file in the root directory you specify<br>
**9/18/2018** An HTML file is also genereated at the root directory you specify in cases when an SMTP Relay isn't available<br>
