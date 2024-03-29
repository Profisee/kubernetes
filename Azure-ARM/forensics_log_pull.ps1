#Pull Product Services, IIS, Event Viewer logs as well as Netstat and TCPConnection logs
$DT = get-date -Format "ddd-MM-dd-yy-HHmmss-ffff-Z" 
mkdir "$env:TEMP\all-Logs\$DT\ProfiseeLogs"
mkdir "$env:TEMP\all-Logs\$DT\EventViewerLogs"
mkdir "$env:TEMP\all-Logs\$DT\TCPLogs"
mkdir "$env:TEMP\all-Logs\$DT\IISLogs"
copy "$env:SystemRoot\System32\winevt\Logs\*" "$env:TEMP\all-Logs\$DT\EventViewerLogs\"
copy c:\profisee\configuration\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\config-log.log
copy c:\profisee\gateway\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\gateway-log.log
copy c:\profisee\services\attachments\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\attachments-log.log
copy c:\profisee\services\auth\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\auth-log.log
copy c:\profisee\services\governance\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\governance-log.log
copy c:\profisee\services\monolith\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\monolith-log.log
copy c:\profisee\services\workflows\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\workflows-log.log
copy c:\profisee\web\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\web-log.log
copy c:\profisee\webportal\logfiles\systemlog.log $env:TEMP\all-Logs\$DT\ProfiseeLogs\webportal-log.log
copy C:\inetpub\logs\LogFiles\W3SVC1\*.log $env:TEMP\all-Logs\$DT\IISLogs\
netstat -anobq > $env:TEMP\all-Logs\$DT\TCPLogs\netstat.txt
Get-NetTCPConnection | Group-Object -Property State, OwningProcess | Select -Property Count, Name, @{Name="ProcessName";Expression={(Get-Process -PID ($_.Name.Split(',')[-1].Trim(' '))).Name}}, Group | Sort Count -Descending | out-file $env:TEMP\all-Logs\$DT\TCPLogs\TCPconnections.txt

#Compress and copy to fileshare
compress-archive -Path "$env:TEMP\all-Logs\$DT\" -DestinationPath "$env:TEMP\all-Logs-$DT.zip"
copy "$env:TEMP\all-Logs-$DT.zip" "C:\fileshare\"

#delete older zipped log files more than 30 days
Get-ChildItem -Path C:\Fileshare\* -Include all-logs-*.zip -Recurse | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | Remove-Item