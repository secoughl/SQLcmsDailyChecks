*update* 9/18/2018 disks percentage is now handled via TSQL, it is no different than any other use of Invoke-DailyCheck. The legacy (remoteWMI) version will be kept in the code for legacy purposes<br>
*update* 9/18/2018 errors now result in a call to Get-Error which timestamps them and dumps them to a text file in the root directory you specify<br>
*update* 9/18/2018 An HTML file is also genereated at the root directory you specify in cases when an SMTP Relay isn't available<br>


Setup:
**1. Deploy all files to a network or local location that the Account performing the checks can access.
2. Update SQLDailyChecks.ps1 (Lines 121-221) in the following manner to fit your environment:**
| Variable | Description |
| --- | --- |
| $reportPath | Root directory for reports and HTML files, please ensure it ends with \ |
| $agOutputFile | File to write results from Availability Group Check |
| $mountSpaceOutputFile | File to write results from Disk Check |
| $jobOutputFile | File to write results from Last Failed Jobs Check |
| $dbaJobOutputFile | File to write results from Disabled DBA Jobs Check |
| $fullRetentionOutputFile | File to write results from Backup Retention Check |
| $bodyUpper | First half of HTML template |
| $bodyLower | Second half of HTML Template |


- Line 122 through 129 - Update these filenames if you change them from the example, these need to be accurate as they control both where the checks are written and what imports occur to generate the HTML email
- Line 131 through 136 - Update your smtprelay, address to send to, address to send from, and finally CMS server name


- $allQuery - Update this for whatever you want to filter off of the results from CMS. Currently shows example Server Group exemptions and wildcard name exemptions ('%OFF%')
- $testQuery - Update this to something simple (like grabbing a single specific instance) and pass it as your scope for rapid testing
- Failed job query - 'name like 'DBA%' - This line exists because, at this customer, all of the jobs we care about across the enterprise start with the name DBA. Please update or remove this line to conform to your environment
- Disabled job query - 'name like 'DBA%' - This line exists because, at this customer, all of the jobs we care about across the enterprise start with the name DBA. Please update or remove this line to conform to your environment
- Please set your retention numbers here based on your backup cadence. We perform a Full every week, a diff every day, and TLOGs every 30 minutes, so we alert on Fulls > 7 days, Diffs > 2 Days, and TLOGs > 100 minutes
- $reportPath - update this to the base directory that holds all of your output files, as well as the upper and lower blocks of HTML for your email template. We use a shared network location for ease of updating and consolidation.  Please ensure there is a trailing \




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
We currently schedule using a SQL Agent Job which runs daily. In order to ensure maximum compatibility in our secured environment, we copy the script down from the network, call PowerShell using our local copy, then at finish delete the local copy. A copy of this job is included in the repo
