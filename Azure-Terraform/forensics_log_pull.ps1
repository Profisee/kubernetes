# Strings to look for
$sqlQuery = "SELECT DATABASEPROPERTYEX('$env:ProfiseeSqlDatabase', 'Updateability') AS Updateability"
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection;
$SqlConnection.ConnectionString = 'Data Source={0};database={1};User ID={2};Password={3}' -f $env:ProfiseeSqlServer,$env:ProfiseeSqlDatabase,$env:ProfiseeSqlUserName,$env:ProfiseeSqlPassword;
$SqlConnection.Open();
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand;
$SqlCmd.CommandText = $sqlQuery;
$SqlCmd.Connection = $SqlConnection;
$result = $SqlCmd.ExecuteScalar();

# Function to check if the SQL Server starts with any of the specified values
if ($result -eq 'READ_ONLY') {
    Write-Output "Database is read-only. Exiting script."
    exit
} else {
    Write-Output "Database is not read-only. Continuing script execution."
}

# Rest of the script
Write-Host "Executing the rest of the script..."
$LogQuery = "SELECT TOP (1000) [Id]
      ,[Message]
      ,[Level]
      ,[TimeStamp]
      ,[Exception]
      ,[LogEvent]
      ,[AssemblyName]
      ,[AssemblyVersion]
      ,[SourceContext]
      ,[EnvironmentUserName]
      ,[MachineName]
  FROM [logging].[tSystemLog]
  order by id desc"
$SqlCmd.CommandText = $LogQuery;
$SqlDataReader = $SqlCmd.ExecuteReader();
$results = @()
while ($SqlDataReader.Read()) {
    $row = @{
        Id                  = $SqlDataReader["Id"]
        Message             = $SqlDataReader["Message"]
        Level               = $SqlDataReader["Level"]
        TimeStamp           = $SqlDataReader["TimeStamp"]
        Exception           = $SqlDataReader["Exception"]
        LogEvent            = $SqlDataReader["LogEvent"]
        AssemblyName        = $SqlDataReader["AssemblyName"]
        AssemblyVersion     = $SqlDataReader["AssemblyVersion"]
        SourceContext       = $SqlDataReader["SourceContext"]
        EnvironmentUserName = $SqlDataReader["EnvironmentUserName"]
        MachineName         = $SqlDataReader["MachineName"]
    }
    $results += [PSCustomObject]$row
}
$SqlDataReader.Close();
$SqlConnection.Close();

# Get hostname of pod to know which pod the logs are from
$hostname = hostname

# Make Webapp name w/ Capital letter
$WebAppName = $env:ProfiseeWebAppName.substring(0, 1).ToUpper() + $env:ProfiseeWebAppName.Substring(1)

New-Item -Path "C:\Fileshare\" -Name "alllogs" -ItemType "directory" -ErrorAction Ignore
# Pull Product Services, IIS, Event Viewer logs as well as Netstat and TCPConnection logs
$DT = get-date -UFormat "%m-%d-%Y-%H%M%S-UTC-%a"
$logsFolder = "$WebAppName-$hostname-$DT"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Config"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Gateway"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Attachments"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Auth"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Governance"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Monolith"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Workflows"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Web"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Webportal"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Monitor"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Data"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\ConnEx"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Chatbot"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Matching"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Matching.BulkScoring"
mkdir "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Modeling"
mkdir "$env:TEMP\all-Logs\$logsFolder\EventViewerLogs"
mkdir "$env:TEMP\all-Logs\$logsFolder\TCPLogs"
mkdir "$env:TEMP\all-Logs\$logsFolder\IISLogs"
mkdir "$env:TEMP\all-logs\$logsFolder\DatabaseLogs"
robocopy "$env:SystemRoot\System32\winevt\Logs\" "$env:TEMP\all-Logs\$logsFolder\EventViewerLogs" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\configuration\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Config" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\gateway\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Gateway" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\attachments\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Attachments" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\auth\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Auth" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\governance\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Governance" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\monolith\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Monolith" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\services\workflows\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Workflows" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Monitor\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Monitor" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Data\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Data" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\ConnEx\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\ConnEx" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Chatbot\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Chatbot" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Matching\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Matching" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Matching.BulkScoring\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Matching.BulkScoring" /E /COPYALL /DCOPY:T
robocopy "C:\Profisee\Services\Modeling\LogFiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Modeling" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\web\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Web" /E /COPYALL /DCOPY:T
robocopy "c:\profisee\webportal\logfiles" "$env:TEMP\all-Logs\$logsFolder\ProfiseeLogs\Webportal" /E /COPYALL /DCOPY:T
robocopy "c:\inetpub\logs\LogFiles\W3SVC1" "$env:TEMP\all-Logs\$logsFolder\IISLogs" /E /COPYALL /DCOPY:T
netstat -anobq > $env:TEMP\all-Logs\$logsFolder\TCPLogs\netstat.txt
Get-NetTCPConnection | Group-Object -Property State, OwningProcess | Select -Property Count, Name, @{Name="ProcessName";Expression={(Get-Process -PID ($_.Name.Split(',')[-1].Trim(' '))).Name}}, Group | Sort Count -Descending | out-file $env:TEMP\all-Logs\$logsFolder\TCPLogs\TCPconnections.txt
$outputCsvPath = "$env:TEMP\all-logs\$logsFolder\DatabaseLogs\db-log.csv"
$results | Select-Object Id, Message, Level, TimeStamp, Exception, LogEvent, AssemblyName, AssemblyVersion, SourceContext, EnvironmentUserName, MachineName | Export-Csv -Path $outputCsvPath -NoTypeInformation -Encoding UTF8
# Compress and copy to fileshare
compress-archive -Path "$env:TEMP\all-Logs\$logsFolder\" -DestinationPath "$env:TEMP\$WebAppName-$hostname-All-Logs-$DT.zip"
copy "$env:TEMP\$WebAppName-$hostname-All-Logs-$DT.zip" "C:\fileshare\alllogs\"

# Delete older zipped log files more than 30 days
Get-ChildItem -Path C:\Fileshare\* -Include *all-logs-*.zip -Recurse | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | Remove-Item