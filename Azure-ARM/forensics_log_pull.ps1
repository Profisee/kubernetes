# Strings to look for
$sqlQuery = "SELECT DATABASEPROPERTYEX('$env:ProfiseeSqlDatabase', 'Updateability') AS Updateability"
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection;
$SqlConnection.ConnectionString = 'Data Source={0};database={1};User ID={2};Password={3}' -f $env:ProfiseeSqlServer,$env:ProfiseeSqlDatabase,$env:ProfiseeSqlUserName,$env:ProfiseeSqlPassword;
$SqlConnection.Open();
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand;
$SqlCmd.CommandText = $sqlQuery;
$SqlCmd.Connection = $SqlConnection;
$result = $SqlCmd.ExecuteScalar();
$SqlConnection.Close();

# Function to check if the SQL Server starts with any of the specified values
if ($result -eq 'READ_ONLY') {
    Write-Output "Database is read-only. Exiting script."
    exit
} else {
    Write-Output "Database is not read-only. Continuing script execution."
}

# Rest of the script
Write-Host "Executing the rest of the script..."

New-Item -Path "C:\Fileshare\" -Name "alllogs" -ItemType "directory" -ErrorAction Ignore
# Pull Product Services, IIS, Event Viewer logs as well as Netstat and TCPConnection logs
$DT = get-date -UFormat "%m-%d-%Y-%H%M%S-UTC-%a"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Config"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Gateway"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Attachments"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Auth"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Governance"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Monolith"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Workflows"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Web"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Webportal"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Monitor"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Data"
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs\ConnEx"
mkdir "$env:TEMP\all-Logs\$DT\EventViewerLogs"
mkdir "$env:TEMP\all-Logs\$DT\TCPLogs"
mkdir "$env:TEMP\all-Logs\$DT\IISLogs"
robocopy "$env:SystemRoot\System32\winevt\Logs\" "$env:TEMP\all-Logs\$DT\EventViewerLogs" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\configuration\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Config" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\gateway\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Gateway" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\attachments\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Attachments" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\auth\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Auth" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\governance\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Governance" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\monolith\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Monolith" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\workflows\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Workflows" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Monitor\LogFiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Monitor" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Data\LogFiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Data" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\ConnEx\LogFiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\ConnEx" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\web\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Web" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\webportal\logfiles" "$env:TEMP\all-Logs\$DT\ProfiseeLogs\Webportal" /E /COPYALL /DCOPY:T
robocopy "c:\inetpub\logs\LogFiles\W3SVC1" "$env:TEMP\all-Logs\$DT\IISLogs" /E /COPYALL /DCOPY:T
netstat -anobq > $env:TEMP\all-Logs\$DT\TCPLogs\netstat.txt
Get-NetTCPConnection | Group-Object -Property State, OwningProcess | Select -Property Count, Name, @{Name="ProcessName";Expression={(Get-Process -PID ($_.Name.Split(',')[-1].Trim(' '))).Name}}, Group | Sort Count -Descending | out-file $env:TEMP\all-Logs\$DT\TCPLogs\TCPconnections.txt

# Make Webapp name w/ Capital letter
$WebAppName = $env:ProfiseeWebAppName.substring(0, 1).ToUpper() + $env:ProfiseeWebAppName.Substring(1)

# Compress and copy to fileshare
compress-archive -Path "$env:TEMP\all-Logs\$DT\" -DestinationPath "$env:TEMP\$WebAppName-All-Logs-$DT.zip"
copy "$env:TEMP\$WebAppName-All-Logs-$DT.zip" "C:\fileshare\alllogs"

# Delete older zipped log files more than 30 days
Get-ChildItem -Path C:\Fileshare\* -Include *all-logs-*.zip -Recurse | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | Remove-Item