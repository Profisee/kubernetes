<#
.SYNOPSIS
    Collects Profisee Master Data Maestro Server troubleshooting data during a live
    fault, most-perishable-first, into a single timestamped ZIP.

.DESCRIPTION
    Run this on the Profisee application server the moment a fault is observed and
    BEFORE anything is restarted. It gathers volatile state first (process/memory,
    live health endpoints, network, SQL blocking) then persistent state (event logs,
    service logs, config), and packages everything into one ZIP.

    The script is READ-ONLY with respect to the Profisee system. It self-elevates,
    time-boxes risky probes, and wraps every collector so one failure never aborts
    the run. SQL server/database are auto-discovered by decrypting the shipped
    connection string in-memory via Profisee's own security library; plaintext
    credentials are never written to disk (config files are copied with their values
    still encrypted).

.PARAMETER OutputPath
    Folder the final ZIP is written to. Default: C:\Fileshare\alllogs
    (the same drop location forensics_log_pull.ps1 uses). Created if missing.

.PARAMETER WebAppName
    Web-app / environment name used in the ZIP file name. Takes precedence over
    the ProfiseeWebAppName environment variable; falls back to 'Profisee'. The
    ZIP is named <WebAppName>-<hostname>-All-Logs-<date>.zip to match
    forensics_log_pull.ps1's convention.

.PARAMETER InstallRoot
    Profisee install root (the folder containing Services, Gateway, Configuration).
    Defaults to the script's own folder; if that is not an install root, falls back
    to process-image discovery. If you pass -InstallRoot explicitly and it is not a
    valid install root (missing Services/Configuration), the script aborts with an
    error rather than silently collecting from a different location.

.PARAMETER HoursBack
    Windows Event Log look-back window, in hours. Default 24.

.PARAMETER MaxLogAgeDays
    Only service log files modified within this many days are collected. Default 3.

.PARAMETER RetentionDays
    After writing the new ZIP, delete *-All-Logs-*.zip bundles in -OutputPath
    older than this many days. Default 30 (matches forensics_log_pull.ps1). Set
    to 0 to disable pruning. Note: with the shared naming convention this also
    prunes forensics_log_pull.ps1 bundles in the same folder, by design.

.PARAMETER ProcessScope
    Which processes the process/dump/IIS collectors capture on a host with more
    than one Profisee version installed:
      InstallRoot (default) - only processes belonging to the install at
                              -InstallRoot (standalone exes matched by image path;
                              in-process services matched by IIS app pool).
      Host                  - every Profisee process on the machine, all versions.

.PARAMETER SqlServer
    SQL Server host for the live SQL snapshot and the system-log table pull.
    Takes precedence over the ProfiseeSqlServer environment variable.

.PARAMETER SqlDatabase
    SQL database (the one containing [logging].[tSystemLog]).
    Takes precedence over the ProfiseeSqlDatabase environment variable.

.PARAMETER SqlUserName
    SQL login user name. Takes precedence over ProfiseeSqlUserName.

.PARAMETER SqlPassword
    SQL login password. Takes precedence over ProfiseeSqlPassword. Prefer the
    environment variable: a value passed here is reconstructed onto the elevated
    relaunch command line and is briefly visible in the process list.

.PARAMETER SqlIntegratedSecurity
    Connect to SQL with Windows authentication (Integrated Security) as the
    account running the script, instead of a SQL login. For installs configured
    for Windows auth (e.g. a typical on-prem deployment). Only -SqlServer/-SqlDatabase
    (or the ProfiseeSql* env vars) are needed; SqlUserName/SqlPassword are ignored.
    Alias: -SqlWindowsAuth.

.PARAMETER IncludeDumps
    Capture full user-mode memory dumps of Profisee processes (best evidence for
    hangs/deadlocks; large files; briefly pauses each process). Off by default.
    Honors -ProcessScope, so only in-scope processes are dumped.

.PARAMETER SkipSql
    Skip the live SQL blocking/waits/active-request snapshot.

.PARAMETER SkipConfigs
    Skip copying appsettings.json / web.config / *.config files.

.PARAMETER KeepStaging
    Do not delete the staging folder after zipping (for debugging the collector).

.PARAMETER PreStop
    Tune the run for a Kubernetes preStop hook under a tight termination grace
    period. Presets (unless individually overridden): -TimeBudgetSeconds 45,
    -HealthTimeoutMs 3000, a single perf-counter sample, and batched IIS queries.
    Also suppresses self-elevation relaunch (see below).

.PARAMETER TimeBudgetSeconds
    Hard wall-clock budget for collection. Once the remaining time falls below the
    packaging reserve, no further collectors start and the script proceeds straight
    to writing the ZIP - guaranteeing a bundle within budget. 0 = unlimited
    (default). -PreStop sets 45 unless you pass a value.

.PARAMETER HealthTimeoutMs
    Per-endpoint timeout for the (parallel) health probes. Default 10000; -PreStop
    lowers it to 3000 unless you pass a value.

.EXAMPLE
    .\Collect-ProfiseeDiagnostics.ps1

.EXAMPLE
    .\Collect-ProfiseeDiagnostics.ps1 -IncludeDumps -HoursBack 48

.EXAMPLE
    # On-prem / Windows-auth install: connect to SQL as the current account.
    .\Collect-ProfiseeDiagnostics.ps1 -SqlIntegratedSecurity -SqlServer '.\MSSQLSERVER16' -SqlDatabase 'Profisee26R2'

.EXAMPLE
    # Kubernetes preStop hook (60s grace period), run by an already-elevated identity:
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\Profisee\Collect-ProfiseeDiagnostics.ps1 -PreStop

.NOTES
    Version 1.0. Designed for Windows PowerShell 5.1 (also runs in PowerShell 7).
#>

[CmdletBinding()]
param(
    [string] $OutputPath    = 'C:\Fileshare\alllogs',
    [string] $WebAppName,
    [string] $InstallRoot   = $PSScriptRoot,
    [int]    $HoursBack     = 24,
    [int]    $MaxLogAgeDays = 3,
    [int]    $RetentionDays = 30,
    [ValidateSet('InstallRoot','Host')]
    [string] $ProcessScope  = 'InstallRoot',
    [string] $SqlServer,
    [string] $SqlDatabase,
    [string] $SqlUserName,
    [string] $SqlPassword,
    [Alias('SqlWindowsAuth')]
    [switch] $SqlIntegratedSecurity,
    [switch] $IncludeDumps,
    [switch] $SkipSql,
    [switch] $SkipConfigs,
    [switch] $KeepStaging,
    [switch] $PreStop,
    [int]    $TimeBudgetSeconds = 0,
    [int]    $HealthTimeoutMs   = 10000
)

$ScriptVersion = '1.0'
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# -PreStop presets: tune for a tight K8s termination grace period. Each preset
# only applies if the operator did not pass that parameter explicitly.
# ---------------------------------------------------------------------------
if ($PreStop) {
    if (-not $PSBoundParameters.ContainsKey('TimeBudgetSeconds')) { $TimeBudgetSeconds = 45 }
    if (-not $PSBoundParameters.ContainsKey('HealthTimeoutMs'))   { $HealthTimeoutMs   = 3000 }
}

# Hard per-invocation timeout (ms) for external commands that can hang mid-run
# (appcmd/netstat/wevtutil) - the start-of-collector budget check cannot interrupt
# an already-running collector, so the spawns themselves must be bounded.
$script:CmdTimeoutMs = if ($PreStop) { 6000 } else { 30000 }

function Invoke-Bounded {
    # Run a native command with a hard timeout; return stdout as lines. On timeout,
    # kill the process and throw so the caller's try/catch logs it and moves on.
    param([string]$File, [string]$ArgString, [int]$TimeoutMs = 0)
    if ($TimeoutMs -le 0) { $TimeoutMs = $script:CmdTimeoutMs }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File; $psi.Arguments = $ArgString
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = New-Object System.Diagnostics.Process; $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    [void]$p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch {}
        throw "'$File $ArgString' exceeded ${TimeoutMs}ms"
    }
    $out = $outTask.Result
    if ($out) { $out -split "`r?`n" } else { @() }
}

function Invoke-Appcmd {
    param([string]$ArgString, [int]$TimeoutMs = 0)
    Invoke-Bounded -File (Join-Path $env:windir 'system32\inetsrv\appcmd.exe') -ArgString $ArgString -TimeoutMs $TimeoutMs
}

# ---------------------------------------------------------------------------
# Self-elevation: relaunch elevated if we are not already an administrator.
# In a preStop hook (or any non-interactive context) a RunAs relaunch cannot
# prompt and would detach - the hook would "succeed" while collection dies with
# the pod. So there we never relaunch; we run best-effort as the current identity
# (containers normally run this already-elevated, so this is just a safety net).
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($PreStop -or -not [Environment]::UserInteractive) {
        Write-Warning 'Not elevated and running non-interactively/preStop - continuing best-effort WITHOUT relaunch; some collectors may be limited.'
    } else {
        Write-Warning 'Not running as Administrator - relaunching elevated...'
        try {
            $argList = @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass',
                         '-File', "`"$PSCommandPath`"")
            foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
                if ($kvp.Value -is [switch]) {
                    if ($kvp.Value.IsPresent) { $argList += "-$($kvp.Key)" }
                } else {
                    $argList += "-$($kvp.Key)"
                    $argList += "`"$($kvp.Value)`""
                }
            }
            Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
        } catch {
            Write-Error "Elevation failed or was declined: $($_.Exception.Message)"
        }
        return
    }
}

# ---------------------------------------------------------------------------
# Resolve install root.
# ---------------------------------------------------------------------------
function Test-InstallRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path (Join-Path $Path 'Services')) -and
           (Test-Path (Join-Path $Path 'Configuration'))
}

$explicitInstallRoot = $PSBoundParameters.ContainsKey('InstallRoot')
if (-not (Test-InstallRoot $InstallRoot)) {
    # An explicitly supplied -InstallRoot that fails validation is a hard error:
    # never silently collect from a different location than the operator asked for.
    if ($explicitInstallRoot) {
        throw ("Specified -InstallRoot '$InstallRoot' is not a valid Profisee install root " +
               "(it must contain both 'Services' and 'Configuration' subfolders). " +
               "Aborting instead of falling back to a different location.")
    }
    # Otherwise (defaulted from the script folder), discover the root from a
    # running Profisee process image.
    $discovered = $null
    foreach ($pname in @('Profisee.Platform.Gateway.Api',
                         'Profisee.MasterDataMaestro.Host')) {
        $p = Get-CimInstance Win32_Process -Filter "Name='$pname.exe'" -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($p -and $p.ExecutablePath) {
            $dir = Split-Path $p.ExecutablePath -Parent
            while ($dir -and -not (Test-InstallRoot $dir)) { $dir = Split-Path $dir -Parent }
            if (Test-InstallRoot $dir) { $discovered = $dir; break }
        }
    }
    if ($discovered) {
        $InstallRoot = $discovered
    } else {
        throw ("Could not locate a Profisee install root (script folder is not an install root " +
               "and no running Profisee process was found). Pass a valid -InstallRoot explicitly.")
    }
}
$InstallRoot = (Resolve-Path $InstallRoot).Path

# ---------------------------------------------------------------------------
# Staging + logging scaffolding.
# ---------------------------------------------------------------------------
$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$hostName = $env:COMPUTERNAME
# ZIP file name aligned with forensics_log_pull.ps1: <WebAppName>-<host>-All-Logs-<DT>.zip
$webApp = if ($WebAppName) { $WebAppName } elseif ($env:ProfiseeWebAppName) { $env:ProfiseeWebAppName } else { 'Profisee' }
if ($webApp.Length -ge 1) { $webApp = $webApp.Substring(0,1).ToUpper() + $webApp.Substring(1) }
$dt        = Get-Date -UFormat '%m-%d-%Y-%H%M%S-UTC-%a'
$stageRoot = Join-Path $env:TEMP "ProfiseeDiag_${hostName}_${stamp}"
$zipName   = "$webApp-$hostName-All-Logs-$dt.zip"
$zipPath   = Join-Path $OutputPath $zipName

$dirs = @{
    Root    = $stageRoot
    Proc    = Join-Path $stageRoot '01_Processes'
    Net     = Join-Path $stageRoot '02_HealthNetwork'
    Sys     = Join-Path $stageRoot '03_System'
    Logs    = Join-Path $stageRoot '04_Logs'
    Config  = Join-Path $stageRoot '05_Config'
    Sql     = Join-Path $stageRoot '06_Sql'
    Dumps   = Join-Path $stageRoot 'Dumps'
}
foreach ($d in $dirs.Values) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$collectionLog = Join-Path $stageRoot 'collection.log'
$script:StepStatus = New-Object System.Collections.Generic.List[object]

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0}  {1,-5}  {2}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Level, $Message
    Add-Content -Path $collectionLog -Value $line
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line -ForegroundColor Gray }
    }
}

# Wall-clock budget: once within the packaging reserve of the deadline, no new
# collector starts, so the run always reaches the ZIP step within the budget.
$script:PackReserveSec = 8
function Test-TimeLeft {
    if (-not $script:Deadline) { return $true }
    return ((Get-Date).AddSeconds($script:PackReserveSec) -lt $script:Deadline)
}

function Invoke-Collector {
    param([string]$Name, [scriptblock]$Action)
    if (-not (Test-TimeLeft)) {
        Write-Log ("SKIP   {0}  (time budget)" -f $Name) 'WARN'
        $script:StepStatus.Add([pscustomobject]@{ Step = $Name; Status = 'Skipped'; Seconds = 0; Error = 'time budget reached' })
        return
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Log "START  $Name"
    $status = 'OK'; $err = ''
    try {
        & $Action
    } catch {
        $status = 'ERROR'; $err = $_.Exception.Message
        Write-Log ("ERROR  {0}: {1}" -f $Name, $err) 'ERROR'
    } finally {
        $sw.Stop()
        if ($status -eq 'OK') {
            Write-Log ("DONE   {0}  ({1:n1}s)" -f $Name, $sw.Elapsed.TotalSeconds)
        }
        $script:StepStatus.Add([pscustomobject]@{
            Step = $Name; Status = $status; Seconds = [math]::Round($sw.Elapsed.TotalSeconds,1); Error = $err
        })
    }
}

function Save-Text { param([string]$Path, $Content) $Content | Out-File -FilePath $Path -Encoding UTF8 -Width 4096 }

Write-Log "Profisee diagnostics collector v$ScriptVersion"
Write-Log "InstallRoot   : $InstallRoot"
Write-Log "Staging       : $stageRoot"
Write-Log "Output ZIP    : $zipPath"
Write-Log "Options       : ProcessScope=$ProcessScope HoursBack=$HoursBack MaxLogAgeDays=$MaxLogAgeDays IncludeDumps=$IncludeDumps SkipSql=$SkipSql SkipConfigs=$SkipConfigs PreStop=$PreStop TimeBudgetSeconds=$TimeBudgetSeconds HealthTimeoutMs=$HealthTimeoutMs"

$overall = [System.Diagnostics.Stopwatch]::StartNew()
$script:Deadline = if ($TimeBudgetSeconds -gt 0) { (Get-Date).AddSeconds($TimeBudgetSeconds) } else { $null }
if ($script:Deadline) { Write-Log ("Time budget   : {0}s (reserve {1}s for packaging)" -f $TimeBudgetSeconds, $script:PackReserveSec) }

# ===========================================================================
# PHASE 0 - Run manifest / environment header
# ===========================================================================
Invoke-Collector 'Manifest' {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $man = [ordered]@{
        CollectedAtLocal = (Get-Date).ToString('o')
        CollectedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        ScriptVersion    = $ScriptVersion
        Operator         = "$env:USERDOMAIN\$env:USERNAME"
        ComputerName     = $hostName
        InstallRoot      = $InstallRoot
        OS               = $os.Caption
        OSVersion        = $os.Version
        LastBootUpTime   = $os.LastBootUpTime.ToString('o')
        UptimeHours      = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours,1)
        TotalMemoryGB    = [math]::Round($cs.TotalPhysicalMemory/1GB,1)
        LogicalProcessors= $cs.NumberOfLogicalProcessors
        PSVersion        = $PSVersionTable.PSVersion.ToString()
        TimeZone         = (Get-TimeZone).Id
        Options          = @{ ProcessScope=$ProcessScope; HoursBack=$HoursBack; MaxLogAgeDays=$MaxLogAgeDays;
                              IncludeDumps=[bool]$IncludeDumps; SkipSql=[bool]$SkipSql;
                              SkipConfigs=[bool]$SkipConfigs; PreStop=[bool]$PreStop;
                              TimeBudgetSeconds=$TimeBudgetSeconds; HealthTimeoutMs=$HealthTimeoutMs }
    }
    $man | ConvertTo-Json -Depth 5 | Out-File (Join-Path $stageRoot 'manifest.json') -Encoding UTF8
}

# Known Profisee process image names (without .exe) + the IIS worker.
$profiseeProcNames = @(
    'Profisee.MasterDataMaestro.Host',
    'Profisee.MasterDataMaestro.WebPortal',
    'Profisee.Platform.Gateway.Api',
    'Profisee.Platform.Auth.Service.Api',
    'Profisee.Platform.Governance.Service.Api',
    'Profisee.Platform.Services.ConnEx.Api',
    'Profisee.Platform.Services.Data.Api',
    'Profisee.Platform.Services.Modeling.Api',
    'Profisee.Platform.Services.Matching.Api',
    'Profisee.Platform.Services.Matching.BulkScoring.Api',
    'Profisee.Platform.Services.Monitor.Api',
    'Profisee.Platform.Services.Chatbot.Api',
    'Profisee.Platform.Services.PortalArtifacts.Api',
    'Profisee.Platform.Services.ScriptRunner.Api',
    'Profisee.Platform.Services.Proflow.Api',
    'Profisee.Platform.Services.Taskman.Api',
    'Profisee.Platform.Services.Mcp.Api',
    'Profisee.Platform.Attachment.Service.Api',
    'Profisee.MasterDataMaestro.Services.Configuration',
    'w3wp'
)

# ---------------------------------------------------------------------------
# Multi-version scoping. On a host with several Profisee versions installed,
# limit process/dump/IIS collection to the install at $InstallRoot.
#
#   * Standalone / out-of-process exes  -> matched by ExecutablePath under root.
#   * In-process services (run inside   -> matched by IIS app pool, where the
#     w3wp)                                pool serves an application whose
#                                          physical path is under $InstallRoot.
# ---------------------------------------------------------------------------
function Get-AppcmdPath {
    $p = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
    if (Test-Path $p) { $p } else { $null }
}

function Get-IisApplications {
    # Cached list of IIS applications: AppPath, Site, Pool, PhysicalPath (expanded).
    # Uses appcmd rather than ServerManager because appcmd honors IIS shared/redirected
    # configuration (redirection.config) and needs no Microsoft.Web.Administration
    # assembly - both matter in containerized/SaaS images. ServerManager's default
    # constructor reads only the local applicationHost.config and can report an empty
    # site when config is redirected.
    if ($null -ne $script:IisAppMap) { return $script:IisAppMap }
    $result = New-Object System.Collections.Generic.List[object]
    $appcmd = Get-AppcmdPath
    if (-not $appcmd) { $script:IisAppMap = $result; return $result }
    try {
        $poolOf = @{}
        foreach ($line in (Invoke-Appcmd 'list app')) {
            if ($line -match '^APP\s+"([^"]+)"\s+\(applicationPool:(.*)\)\s*$') {
                $poolOf[$Matches[1].TrimEnd('/')] = $Matches[2]
            }
        }
        foreach ($line in (Invoke-Appcmd 'list vdir')) {
            if ($line -match '^VDIR\s+"([^"]+)"\s+\(physicalPath:(.*)\)\s*$') {
                $appPath = $Matches[1].TrimEnd('/')
                if (-not $poolOf.ContainsKey($appPath)) { continue }   # keep only application root vdirs
                $result.Add([pscustomobject]@{
                    AppPath      = $appPath
                    Site         = ($appPath -split '/')[0]
                    Pool         = $poolOf[$appPath]
                    PhysicalPath = [Environment]::ExpandEnvironmentVariables($Matches[2])
                })
            }
        }
    } catch {
        Write-Log "  IIS app enumeration (appcmd) failed: $($_.Exception.Message)" 'WARN'
    }
    $script:IisAppMap = $result
    return $result
}

function Resolve-InstallPools {
    # App pools serving an application whose physical path is under $Root.
    param([string]$Root)
    $pools = @(Get-IisApplications | Where-Object { $_.PhysicalPath -like "$Root*" } |
               Select-Object -ExpandProperty Pool)
    return ($pools | Sort-Object -Unique)
}

function Get-InstallSites {
    # Sites hosting at least one application whose physical path is under $Root,
    # with each site's numeric Id and (env-expanded) IIS log directory.
    param([string]$Root)
    $sites = New-Object System.Collections.Generic.List[object]
    $appcmd = Get-AppcmdPath
    if (-not $appcmd) { return $sites }
    $matchSites = @(Get-IisApplications | Where-Object { $_.PhysicalPath -like "$Root*" } |
                    Select-Object -ExpandProperty Site -Unique)
    if (-not $matchSites.Count) { return $sites }
    try {
        foreach ($line in (Invoke-Appcmd 'list site')) {
            if ($line -match '^SITE\s+"([^"]+)"\s+\(id:(\d+)') {
                $name = $Matches[1]; $id = [int]$Matches[2]
                if ($matchSites -notcontains $name) { continue }
                $logDir = (Invoke-Appcmd "list site `"$name`" /text:logFile.directory") | Select-Object -First 1
                # appcmd can emit an error string; accept only a real path, else default.
                if ([string]::IsNullOrWhiteSpace($logDir) -or ($logDir -notmatch '^([A-Za-z]:\\|%)')) {
                    $logDir = '%SystemDrive%\inetpub\logs\LogFiles'
                }
                $sites.Add([pscustomobject]@{
                    Name   = $name
                    Id     = $id
                    LogDir = [Environment]::ExpandEnvironmentVariables($logDir)
                })
            }
        }
    } catch {
        Write-Log "  IIS site resolution (appcmd) failed: $($_.Exception.Message)" 'WARN'
    }
    return $sites
}

function Get-InstallSiteToken {
    # Fallback when IIS metadata is unavailable: derive the site path segment
    # (e.g. 'profisee26r2') from this install's config so w3wp pools that embed
    # the site name can still be matched by substring.
    param([string]$Root)
    $cfg = Get-ChildItem $Root -Recurse -Filter 'appsettings.json' -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if (-not $cfg) { return $null }
    try {
        $j = Get-Content $cfg.FullName -Raw | ConvertFrom-Json
        foreach ($prop in $j.ProfiseeAppSettings.PSObject.Properties) {
            if ($prop.Name -like '*HealthUrl' -and $prop.Value -match 'https?://[^/]+/([^/]+)/') {
                return $Matches[1].ToLower()
            }
        }
    } catch {}
    return $null
}

function Get-ProcessAppPool {
    param([string]$CommandLine)
    if ($CommandLine -and $CommandLine -match '-ap\s+"([^"]+)"') { return $Matches[1] }
    return $null
}

function Test-BelongsToInstall {
    # $Proc is a Win32_Process CIM instance.
    param($Proc)
    if ($Proc.ExecutablePath -and $Proc.ExecutablePath -like "$InstallRoot*") { return $true }
    if ($Proc.Name -ieq 'w3wp.exe') {
        $pool = Get-ProcessAppPool $Proc.CommandLine
        if (-not $pool) { return $false }
        if ($script:OurPools -contains $pool) { return $true }
        # Fallback: no authoritative pool list, match by embedded site token.
        if ($script:OurPools.Count -eq 0 -and $script:SiteToken -and
            $pool.ToLower().Contains($script:SiteToken)) { return $true }
        return $false
    }
    return $false
}

if ($ProcessScope -eq 'InstallRoot') {
    $script:OurPools  = @(Resolve-InstallPools -Root $InstallRoot)
    $script:SiteToken = Get-InstallSiteToken -Root $InstallRoot
    if ($script:OurPools.Count) {
        Write-Log ("Scope         : InstallRoot - {0} IIS app pool(s): {1}" -f $script:OurPools.Count, ($script:OurPools -join ', '))
    } elseif ($script:SiteToken) {
        Write-Log ("Scope         : InstallRoot - IIS metadata unavailable; w3wp matched by site token '{0}'" -f $script:SiteToken) 'WARN'
    } else {
        Write-Log 'Scope         : InstallRoot - could not resolve app pools or site token; w3wp will be matched by ExecutablePath only' 'WARN'
    }
} else {
    $script:OurPools  = @()
    $script:SiteToken = $null
    Write-Log 'Scope         : Host - collecting all Profisee processes across every installed version.'
}

# ===========================================================================
# PHASE 1 - Volatile process, IIS runtime and (optional) memory dumps
# ===========================================================================
Invoke-Collector 'Process snapshot' {
    $nameSet = @{}; foreach ($n in $profiseeProcNames) { $nameSet["$n.exe"] = $true }
    $cim = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    # Candidate = any known Profisee image name, anything named Profisee.*, or w3wp.
    $candidates = $cim | Where-Object {
        $nameSet.ContainsKey($_.Name) -or $_.Name -like 'Profisee.*' -or $_.Name -ieq 'w3wp.exe'
    }
    $rows = foreach ($c in $candidates) {
        if ($ProcessScope -eq 'InstallRoot' -and -not (Test-BelongsToInstall $c)) { continue }
        $proc = Get-Process -Id $c.ProcessId -ErrorAction SilentlyContinue
        $startTime = $null
        if ($proc) { try { $startTime = $proc.StartTime.ToString('o') } catch {} }
        [pscustomobject]@{
            Name          = $c.Name
            PID           = $c.ProcessId
            AppPool       = Get-ProcessAppPool $c.CommandLine
            CPUSeconds    = if ($proc) { [math]::Round($proc.CPU,1) } else { $null }
            WorkingSetMB  = if ($proc) { [math]::Round($proc.WorkingSet64/1MB,1) } else { $null }
            PrivateMB     = if ($proc) { [math]::Round($proc.PrivateMemorySize64/1MB,1) } else { $null }
            Threads       = if ($proc) { $proc.Threads.Count } else { $null }
            Handles       = if ($proc) { $proc.HandleCount } else { $null }
            StartTime     = $startTime
            ExecutablePath = $c.ExecutablePath
            CommandLine   = $c.CommandLine
        }
    }
    $rows = @($rows)
    $rows | Sort-Object Name, PID | Select-Object Name, PID, AppPool, CPUSeconds, WorkingSetMB, PrivateMB, Threads, Handles, StartTime, ExecutablePath |
        Format-Table -AutoSize | Out-File (Join-Path $dirs.Proc 'processes.txt') -Encoding UTF8 -Width 4096
    $rows | Export-Csv (Join-Path $dirs.Proc 'processes.csv') -NoTypeInformation
    $script:ProfiseePids = @($rows.PID)
    Write-Log ("  captured {0} process(es) (scope={1})" -f $rows.Count, $ProcessScope)
}

Invoke-Collector 'IIS runtime state' {
    $appcmd = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
    if (-not (Test-Path $appcmd)) { Write-Log '  appcmd.exe not found - IIS not installed?' 'WARN'; return }

    $scoped = ($ProcessScope -eq 'InstallRoot' -and $script:OurPools.Count -gt 0)
    if ($scoped -and -not $PreStop) {
        Write-Log ("  scoping IIS state to {0} pool(s)" -f $script:OurPools.Count)
        try { ($script:OurPools | ForEach-Object { Invoke-Appcmd "list wp /apppool:`"$_`"" }) |
                Out-File (Join-Path $dirs.Proc 'iis_workerprocesses.txt') -Encoding UTF8 } catch { Write-Log "  iis wp: $($_.Exception.Message)" 'WARN' }
        try { ($script:OurPools | ForEach-Object { Invoke-Appcmd "list apppool `"$_`"" }) |
                Out-File (Join-Path $dirs.Proc 'iis_apppools.txt') -Encoding UTF8 } catch { Write-Log "  iis apppool: $($_.Exception.Message)" 'WARN' }
        # Currently-executing requests per pool - the smoking gun for an in-progress hang.
        # Tight 4s cap: this query can stall waiting on a worker RPC and is low-criticality.
        try { ($script:OurPools | ForEach-Object { Invoke-Appcmd "list request /apppool:`"$_`" /elapsed:1000" 4000 }) |
                Out-File (Join-Path $dirs.Proc 'iis_active_requests.txt') -Encoding UTF8 } catch { Write-Log "  iis requests: $($_.Exception.Message)" 'WARN' }
    } else {
        # Host-wide batched calls (few appcmd spawns); filter wp/apppool to our pools
        # in-script when scoped. Used for -PreStop (fast) and for Host scope.
        if ($scoped) {
            $poolSet = @{}; foreach ($p in $script:OurPools) { $poolSet[$p.ToLower()] = $true }
            Write-Log ("  scoping IIS state to {0} pool(s) (batched)" -f $script:OurPools.Count)
        }
        try {
            $allWp = Invoke-Appcmd 'list wp'
            if ($scoped) { $allWp = $allWp | Where-Object { $_ -match '\(applicationPool:([^\)]+)\)' -and $poolSet.ContainsKey($Matches[1].ToLower()) } }
            $allWp | Out-File (Join-Path $dirs.Proc 'iis_workerprocesses.txt') -Encoding UTF8
        } catch { Write-Log "  iis wp: $($_.Exception.Message)" 'WARN' }
        try {
            $allAp = Invoke-Appcmd 'list apppool'
            if ($scoped) { $allAp = $allAp | Where-Object { $_ -match '^APPPOOL\s+"([^"]+)"' -and $poolSet.ContainsKey($Matches[1].ToLower()) } }
            $allAp | Out-File (Join-Path $dirs.Proc 'iis_apppools.txt') -Encoding UTF8
        } catch { Write-Log "  iis apppool: $($_.Exception.Message)" 'WARN' }
        try { (Invoke-Appcmd 'list request /elapsed:1000' 4000) | Out-File (Join-Path $dirs.Proc 'iis_active_requests.txt') -Encoding UTF8 }
        catch { Write-Log "  iis requests: $($_.Exception.Message)" 'WARN' }
    }
    # Site inventory is small and useful for context regardless of scope.
    try { (Invoke-Appcmd 'list site') | Out-File (Join-Path $dirs.Proc 'iis_sites.txt') -Encoding UTF8 }
    catch { Write-Log "  iis sites: $($_.Exception.Message)" 'WARN' }

    # At-a-glance app-pool state summary parsed from appcmd, with any pool that is
    # NOT Started surfaced at the top - a stopped pool is a high-signal fault clue.
    try {
        $rows = foreach ($line in (Invoke-Appcmd 'list apppool')) {
            # APPPOOL "Name" (MgdVersion:v4.0,MgdMode:Integrated,state:Started)
            if ($line -notmatch '^APPPOOL\s+"([^"]+)"\s+\((.*)\)\s*$') { continue }
            $name = $Matches[1]; $attrs = $Matches[2]
            if ($scoped -and ($script:OurPools -notcontains $name)) { continue }
            $state = if ($attrs -match 'state:([^,\)]+)')      { $Matches[1] } else { 'Unknown' }
            $mode  = if ($attrs -match 'MgdMode:([^,\)]+)')     { $Matches[1] } else { '' }
            $ver   = if ($attrs -match 'MgdVersion:([^,\)]*)')  { $Matches[1] } else { '' }
            $auto  = if ($PreStop) { '' } else { (Invoke-Appcmd "list apppool `"$name`" /text:autoStart") | Select-Object -First 1 }
            [pscustomobject]@{
                AppPool        = $name
                State          = $state
                Started        = ($state -eq 'Started')
                AutoStart      = $auto
                PipelineMode   = $mode
                RuntimeVersion = $ver
            }
        }
        $rows = @($rows) | Sort-Object Started, AppPool   # not-Started first
        if ($rows.Count) {
            $rows | Format-Table -AutoSize |
                Out-File (Join-Path $dirs.Proc 'iis_apppool_state.txt') -Encoding UTF8 -Width 4096
            $rows | Export-Csv (Join-Path $dirs.Proc 'iis_apppool_state.csv') -NoTypeInformation
            $notStarted = @($rows | Where-Object { -not $_.Started })
            if ($notStarted.Count) {
                Write-Log ("  APP POOLS NOT STARTED: {0}" -f (($notStarted | ForEach-Object { "$($_.AppPool)=$($_.State)" }) -join ', ')) 'WARN'
            } else {
                Write-Log ("  all {0} app pool(s) Started" -f $rows.Count)
            }
        } else {
            Write-Log '  no app pools matched for state summary' 'WARN'
        }
    } catch {
        Write-Log "  app-pool state summary failed: $($_.Exception.Message)" 'WARN'
    }
}

if ($IncludeDumps) {
    Invoke-Collector 'Memory dumps' {
        $comsvcs = Join-Path $env:windir 'System32\comsvcs.dll'
        $procdump = Get-Command procdump.exe -ErrorAction SilentlyContinue
        foreach ($procId in ($script:ProfiseePids | Sort-Object -Unique)) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            $dumpFile = Join-Path $dirs.Dumps ("{0}_{1}.dmp" -f $p.Name, $procId)
            try {
                if ($procdump) {
                    & $procdump.Source -accepteula -ma $procId "$dumpFile" 2>&1 | Out-Null
                } else {
                    # Built-in full dump via MiniDumpWriteDump, no external tooling.
                    & rundll32.exe $comsvcs, MiniDump $procId "$dumpFile" full 2>&1 | Out-Null
                }
                if (Test-Path $dumpFile) {
                    Write-Log ("  dumped PID {0} ({1}) -> {2:n0} MB" -f $procId, $p.Name, ((Get-Item $dumpFile).Length/1MB))
                }
            } catch {
                Write-Log ("  dump failed for PID {0}: {1}" -f $procId, $_.Exception.Message) 'WARN'
            }
        }
    }
} else {
    Write-Log 'Memory dumps skipped (-IncludeDumps not set).'
}

# ===========================================================================
# PHASE 2 - Live health endpoints + network state
# ===========================================================================
Invoke-Collector 'Live health endpoints' {
    # Gather the localhost *HealthUrl base paths from config, then build the
    # actual probe URLs per component type:
    #   * platform root (WebHealthUrl '.../api/api/')  -> '.../api/'
    #   * REST gateway                                 -> '.../rest/health'
    #   * every other microservice ('.../api/<svc>/')  -> append '/health'
    #     (Auth is mounted at '.../auth/', so it becomes '.../auth/health'.)
    $urls = New-Object System.Collections.Generic.HashSet[string]
    $siteBase = $null
    Get-ChildItem $InstallRoot -Recurse -Filter 'appsettings.json' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if (-not $j.ProfiseeAppSettings) { return }
            $j.ProfiseeAppSettings.PSObject.Properties |
                Where-Object { $_.Name -like '*HealthUrl' -and $_.Value -like 'http*localhost*' } |
                ForEach-Object {
                    $key = $_.Name; $val = [string]$_.Value
                    # site base = scheme://host/<siteSegment>  (e.g. http://localhost/profisee26r2)
                    if (-not $siteBase -and $val -match '^(https?://[^/]+/[^/]+)') { $siteBase = $Matches[1] }
                    if ($key -eq 'WebHealthUrl') {
                        [void]$urls.Add(($val -replace '/api/api/?$', '/api/'))
                    } else {
                        [void]$urls.Add(($val.TrimEnd('/') + '/health'))
                    }
                }
        } catch {}
    }
    if ($siteBase) { [void]$urls.Add("$siteBase/rest/health") }
    if ($urls.Count -eq 0) { Write-Log '  no localhost health URLs found in config' 'WARN'; return }

    # Probe all endpoints in parallel with a bounded per-endpoint timeout, so a
    # hung/unresponsive endpoint can't stall the run (critical under a time budget).
    $probe = {
        param($Url, $TimeoutMs)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $out = [ordered]@{ Url = $Url; Code = $null; LatencyMs = $null; BodyPreview = $null; Error = $null }
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Timeout = $TimeoutMs; $req.ReadWriteTimeout = $TimeoutMs
            $req.Method = 'GET'; $req.AllowAutoRedirect = $true
            $resp = $req.GetResponse()
            $out.Code = [int]$resp.StatusCode
            $rd = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body = $rd.ReadToEnd(); $rd.Close(); $resp.Close()
            if ($body.Length -gt 2000) { $body = $body.Substring(0,2000) + '...[truncated]' }
            $out.BodyPreview = $body
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $out.Code = [int]$_.Exception.Response.StatusCode
                try { $rd = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $out.BodyPreview = $rd.ReadToEnd(); $rd.Close() } catch {}
            }
            $out.Error = $_.Exception.Message
        } catch {
            $out.Error = $_.Exception.Message
        } finally { $sw.Stop(); $out.LatencyMs = [int]$sw.Elapsed.TotalMilliseconds }
        [pscustomobject]$out
    }
    $urlList = @($urls | Sort-Object)
    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min(24, [Math]::Max(1, $urlList.Count)))
    $pool.Open()
    $inflight = foreach ($u in $urlList) {
        $ps = [powershell]::Create(); $ps.RunspacePool = $pool
        [void]$ps.AddScript($probe).AddArgument($u).AddArgument($HealthTimeoutMs)
        [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    }
    # Overall wall-clock cap (per-endpoint timeout + slack) so a stuck runspace
    # can't hang the phase; endpoints not done by the cap are recorded as pending.
    $capMs = $HealthTimeoutMs + 3000
    $capSw = [System.Diagnostics.Stopwatch]::StartNew()
    $results = New-Object System.Collections.Generic.List[object]
    $pending = 0
    foreach ($j in $inflight) {
        $remain = [int][Math]::Max(0, $capMs - $capSw.ElapsedMilliseconds)
        if ($j.Handle.AsyncWaitHandle.WaitOne($remain)) {
            try { $results.Add(($j.PS.EndInvoke($j.Handle))) } catch {}
        } else {
            $pending++; try { $j.PS.Stop() } catch {}
        }
        $j.PS.Dispose()
    }
    $pool.Close(); $pool.Dispose()
    $results | Select-Object Code, LatencyMs, Url, Error |
        Sort-Object Url | Format-Table -AutoSize | Out-File (Join-Path $dirs.Net 'health_summary.txt') -Encoding UTF8 -Width 4096
    $results | ConvertTo-Json -Depth 4 | Out-File (Join-Path $dirs.Net 'health_detail.json') -Encoding UTF8
    Write-Log ("  probed {0}/{1} health endpoints in parallel (timeout {2}ms{3})" -f `
        $results.Count, $urlList.Count, $HealthTimeoutMs, $(if ($pending) { ", $pending pending" } else { '' }))
}

Invoke-Collector 'Network state' {
    # -anobq: all connections + listening/bound (-q), numeric (-n), owning PID (-o),
    # and owning executable/component (-b, needs elevation - we are elevated).
    # Bounded: -b can hang resolving executables, which we can't afford under budget.
    $netLines = @()
    try { $netLines = Invoke-Bounded -File 'netstat.exe' -ArgString '-anobq' }
    catch { Write-Log "  netstat timed out/failed: $($_.Exception.Message)" 'WARN' }
    $netLines | Out-File (Join-Path $dirs.Net 'netstat.txt') -Encoding UTF8
    & ipconfig /all 2>&1 | Out-File (Join-Path $dirs.Net 'ipconfig.txt') -Encoding UTF8

    # Netstat/perf counters are host-wide; flag the connections owned by the
    # process set we scoped to, so this install's traffic stays identifiable.
    $ourPids = @($script:ProfiseePids)
    if ($ourPids.Count) {
        $pidSet = @{}; foreach ($id in $ourPids) { $pidSet["$id"] = $true }
        # Preserve the netstat column header (the 'Proto ... PID' line) atop the filtered rows.
        $header = $netLines | Where-Object { $_ -match '^\s*Proto\s' } | Select-Object -First 1
        $scoped = $netLines | Where-Object { $_ -match '\s(\d+)\s*$' -and $pidSet.ContainsKey($Matches[1]) }
        @($header) + @($scoped) | Where-Object { $_ } |
            Out-File (Join-Path $dirs.Net 'netstat_scoped_pids.txt') -Encoding UTF8
        Save-Text (Join-Path $dirs.Net 'scoped_pids.txt') (
            "ProcessScope=$ProcessScope`nPIDs in scope: " + ($ourPids -join ', '))
    }

    try {
        Get-NetTCPConnection -ErrorAction Stop |
            Group-Object State | Select-Object Name, Count |
            Format-Table -AutoSize | Out-File (Join-Path $dirs.Net 'tcp_state_summary.txt') -Encoding UTF8

        # Connection counts grouped by State + OwningProcess, with the process name
        # resolved, highest count first. Surfaces things like a CLOSE_WAIT/TIME_WAIT
        # flood pinned to one service (Group name is "<State>, <PID>").
        Get-NetTCPConnection -ErrorAction Stop |
            Group-Object -Property State, OwningProcess |
            Select-Object Count, Name,
                @{Name='ProcessName';Expression={
                    (Get-Process -Id ($_.Name.Split(',')[-1].Trim(' ')) -ErrorAction SilentlyContinue).Name }},
                @{Name='InScope';Expression={ $ourPids -contains [int]($_.Name.Split(',')[-1].Trim(' ')) }} |
            Sort-Object Count -Descending |
            Format-Table Count, Name, ProcessName, InScope -AutoSize |
            Out-File (Join-Path $dirs.Net 'tcp_by_state_process.txt') -Encoding UTF8 -Width 4096

        Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Select-Object LocalAddress, LocalPort, OwningProcess,
                @{n='InScope';e={ $ourPids -contains $_.OwningProcess }} |
            Sort-Object LocalPort | Format-Table -AutoSize |
            Out-File (Join-Path $dirs.Net 'listening_ports.txt') -Encoding UTF8
    } catch {
        Write-Log '  Get-NetTCPConnection unavailable; netstat captured instead' 'WARN'
    }
}

# ===========================================================================
# PHASE 3 - System context: event logs, perf counters, disk, .NET
# ===========================================================================
Invoke-Collector 'Windows event logs' {
    $ms = $HoursBack * 3600 * 1000
    $q  = "*[System[TimeCreated[timediff(@SystemTime) <= $ms]]]"
    foreach ($log in @('Application','System')) {
        $evtx = Join-Path $dirs.Sys "$log.evtx"
        # Bounded: exporting a large log can be slow; don't let it eat the budget.
        try { [void](Invoke-Bounded -File 'wevtutil.exe' -ArgString "epl $log `"$evtx`" /q:`"$q`" /ow:true") }
        catch { Write-Log "  wevtutil $log export timed out/failed: $($_.Exception.Message)" 'WARN' }
    }
    $since = (Get-Date).AddHours(-$HoursBack)
    foreach ($log in @('Application','System')) {
        try {
            Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $since; Level = 1,2,3 } -ErrorAction Stop |
                Select-Object TimeCreated, Level, Id, ProviderName, Message |
                Format-Table -AutoSize -Wrap |
                Out-File (Join-Path $dirs.Sys "${log}_errors_warnings.txt") -Encoding UTF8 -Width 4096
        } catch {
            Write-Log "  no error/warning events in $log for the window" 'WARN'
        }
    }
}

Invoke-Collector 'Performance counters' {
    $counters = @(
        '\Processor(_Total)\% Processor Time',
        '\Memory\Available MBytes',
        '\Memory\% Committed Bytes In Use',
        '\PhysicalDisk(_Total)\Current Disk Queue Length',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
    )
    try {
        # A single snapshot under -PreStop (saves ~3s); a short trend otherwise.
        $perfSamples = if ($PreStop) { 1 } else { 3 }
        (Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples $perfSamples -ErrorAction Stop).CounterSamples |
            Select-Object Timestamp, Path, CookedValue |
            Format-Table -AutoSize | Out-File (Join-Path $dirs.Sys 'perf_counters.txt') -Encoding UTF8 -Width 4096
    } catch {
        Write-Log "  perf counters partially/entirely unavailable: $($_.Exception.Message)" 'WARN'
    }
}

Invoke-Collector 'System info' {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
        Select-Object DeviceID,
            @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
            @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}},
            @{n='FreePct';e={ if($_.Size){[math]::Round(100*$_.FreeSpace/$_.Size,1)}else{0} }} |
        Format-Table -AutoSize | Out-File (Join-Path $dirs.Sys 'disk_space.txt') -Encoding UTF8
    try { & dotnet --list-runtimes 2>&1 | Out-File (Join-Path $dirs.Sys 'dotnet_runtimes.txt') -Encoding UTF8 } catch {}
    try {
        Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending |
            Select-Object -First 25 HotFixID, Description, InstalledOn |
            Format-Table -AutoSize | Out-File (Join-Path $dirs.Sys 'recent_hotfixes.txt') -Encoding UTF8
    } catch {}
    Get-Service | Where-Object { $_.DisplayName -like '*Profisee*' -or $_.Name -like '*Profisee*' } |
        Select-Object Name, DisplayName, Status, StartType |
        Format-Table -AutoSize | Out-File (Join-Path $dirs.Sys 'profisee_services.txt') -Encoding UTF8
}

# ===========================================================================
# PHASE 4 - Persistent artifacts: service logs
# ===========================================================================
Invoke-Collector 'Service logs' {
    $cutoff = (Get-Date).AddDays(-$MaxLogAgeDays)
    $logRoots = Get-ChildItem $InstallRoot -Recurse -Directory -Filter 'LogFiles' -ErrorAction SilentlyContinue
    $count = 0
    foreach ($lr in $logRoots) {
        # Preserve a readable relative structure: <parentServiceName>\<file>
        $serviceName = Split-Path (Split-Path $lr.FullName -Parent) -Leaf
        $dest = Join-Path $dirs.Logs $serviceName
        Get-ChildItem $lr.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $cutoff -and $_.Extension -match '\.(log|txt|json)$' } |
            ForEach-Object {
                if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                Copy-Item $_.FullName -Destination $dest -Force
                $count++
            }
    }
    Write-Log ("  copied {0} log files (<= {1} days old)" -f $count, $MaxLogAgeDays)
}

Invoke-Collector 'IIS logs' {
    # W3SVC request logs for the site(s) hosting this install, same age window
    # as the service logs. Site log dir + numeric Id come from IIS metadata.
    $sites = @(Get-InstallSites -Root $InstallRoot)
    if (-not $sites.Count) { Write-Log '  no IIS sites resolved for this install; skipping IIS logs' 'WARN'; return }
    $cutoff = (Get-Date).AddDays(-$MaxLogAgeDays)
    $count = 0
    foreach ($s in $sites) {
        $srcDir = Join-Path $s.LogDir ("W3SVC{0}" -f $s.Id)
        if (-not (Test-Path $srcDir)) { Write-Log ("  IIS log dir not found: {0}" -f $srcDir) 'WARN'; continue }
        $safeName = ($s.Name -replace '[^\w.-]', '_')
        $dest = Join-Path $dirs.Logs ("IIS_{0}_W3SVC{1}" -f $safeName, $s.Id)
        Get-ChildItem $srcDir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $cutoff } |
            ForEach-Object {
                if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                Copy-Item $_.FullName -Destination $dest -Force
                $count++
            }
    }
    Write-Log ("  copied {0} IIS log file(s) from {1} site(s) (<= {2} days old)" -f $count, $sites.Count, $MaxLogAgeDays)
}

# ===========================================================================
# PHASE 5 - Config files (encrypted values copied as-is)
# ===========================================================================
if (-not $SkipConfigs) {
    Invoke-Collector 'Config files' {
        $count = 0
        Get-ChildItem $InstallRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like 'appsettings*.json' -or
                $_.Name -ieq 'web.config' -or
                ($_.Extension -ieq '.config' -and $_.FullName -notmatch '\\bin\\roslyn\\')
            } |
            ForEach-Object {
                $rel = $_.FullName.Substring($InstallRoot.Length).TrimStart('\')
                $dest = Join-Path $dirs.Config $rel
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item $_.FullName -Destination $dest -Force
                $count++
            }
        Write-Log ("  copied {0} config files (connection strings remain ENCRYPTED)" -f $count)
    }
} else {
    Write-Log 'Config collection skipped (-SkipConfigs set).'
}

# ---------------------------------------------------------------------------
# SQL helpers shared by the DMV snapshot and the system-log table pull.
# ---------------------------------------------------------------------------
function Initialize-DiagSqlClient {
    param([string]$Root)
    if ('System.Data.SqlClient.SqlConnection' -as [type]) { return $true }
    try { Add-Type -AssemblyName System.Data -ErrorAction Stop } catch {}
    if ('System.Data.SqlClient.SqlConnection' -as [type]) { return $true }
    $sqlDll = Get-ChildItem $Root -Recurse -Filter 'System.Data.SqlClient.dll' -ErrorAction SilentlyContinue |
              Select-Object -First 1
    if ($sqlDll) { try { Add-Type -Path $sqlDll.FullName -ErrorAction Stop } catch {} }
    return [bool]('System.Data.SqlClient.SqlConnection' -as [type])
}

# ===========================================================================
# PHASE 6 - Live SQL snapshot (DMV blocking/waits) + recent system-log rows
# ===========================================================================
if (-not $SkipSql) {
    Invoke-Collector 'SQL live snapshot' {
        # Server/Database come from the ProfiseeSql* environment variables the platform
        # injects (same source as forensics_log_pull.ps1); explicit -Sql* parameters
        # take precedence. Auth is SQL login by default, or the Windows identity when
        # -SqlIntegratedSecurity is set. No connection-string decryption.
        $sqlServer   = if ($SqlServer)   { $SqlServer }   else { $env:ProfiseeSqlServer }
        $sqlDatabase = if ($SqlDatabase) { $SqlDatabase } else { $env:ProfiseeSqlDatabase }

        $missing = @()
        if (-not $sqlServer)   { $missing += 'Server (-SqlServer / ProfiseeSqlServer)' }
        if (-not $sqlDatabase) { $missing += 'Database (-SqlDatabase / ProfiseeSqlDatabase)' }

        if ($SqlIntegratedSecurity) {
            if ($missing.Count) {
                Write-Log ("  SQL target unavailable ({0}); skipping SQL" -f ($missing -join '; ')) 'WARN'; return
            }
            # Windows auth as the (elevated) account running the script - no secret.
            $connStr = 'Data Source={0};Initial Catalog={1};Integrated Security=SSPI;Connect Timeout=5;Application Name=ProfiseeDiag' -f `
                       $sqlServer, $sqlDatabase
            $identity = "$env:USERDOMAIN\$env:USERNAME"
            Write-Log ("  SQL target: Data Source={0}; Initial Catalog={1}; Windows auth as {2}" -f $sqlServer, $sqlDatabase, $identity)
            Save-Text (Join-Path $dirs.Sql 'resolved_target.txt') (
                "Data Source     : $sqlServer`nInitial Catalog : $sqlDatabase`nAuthentication  : Windows (Integrated Security) as $identity")
        } else {
            $sqlUser = if ($SqlUserName) { $SqlUserName } else { $env:ProfiseeSqlUserName }
            $sqlPass = if ($SqlPassword) { $SqlPassword } else { $env:ProfiseeSqlPassword }
            if (-not $sqlUser) { $missing += 'UserName (-SqlUserName / ProfiseeSqlUserName)' }
            if (-not $sqlPass) { $missing += 'Password (-SqlPassword / ProfiseeSqlPassword)' }
            if ($missing.Count) {
                Write-Log ("  SQL credentials unavailable ({0}); skipping SQL (use -SqlIntegratedSecurity for Windows auth)" -f ($missing -join '; ')) 'WARN'; return
            }
            # SQL auth, mirroring forensics_log_pull.ps1's connection string.
            $connStr = 'Data Source={0};Initial Catalog={1};User ID={2};Password={3};Connect Timeout=5;Application Name=ProfiseeDiag' -f `
                       $sqlServer, $sqlDatabase, $sqlUser, $sqlPass
            Write-Log ("  SQL target: Data Source={0}; Initial Catalog={1}; User ID={2}" -f $sqlServer, $sqlDatabase, $sqlUser)
            # Record resolved target WITHOUT the password.
            Save-Text (Join-Path $dirs.Sql 'resolved_target.txt') (
                "Data Source     : $sqlServer`nInitial Catalog : $sqlDatabase`nUser ID         : $sqlUser`nPassword        : [redacted - not written]")
        }

        if (-not (Initialize-DiagSqlClient -Root $InstallRoot)) {
            Write-Log '  no SQL client available; skipping SQL' 'WARN'; return
        }

        $queries = [ordered]@{
            'active_requests' = @'
SELECT r.session_id, r.status, r.command, r.wait_type, r.wait_time,
       r.blocking_session_id, r.cpu_time, r.total_elapsed_time, r.reads, r.writes,
       s.login_name, s.host_name, s.program_name,
       SUBSTRING(t.text,1,2000) AS sql_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;
'@
            'blocking_chains' = @'
SELECT r.blocking_session_id, r.session_id AS blocked_session_id,
       r.wait_type, r.wait_time, r.wait_resource,
       SUBSTRING(t.text,1,2000) AS blocked_sql
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;
'@
            'top_waits' = @'
SELECT TOP 25 wait_type, waiting_tasks_count,
       wait_time_ms, max_wait_time_ms, signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('SLEEP_TASK','BROKER_TASK_STOP','CLR_AUTO_EVENT',
      'LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH','WAITFOR','CHECKPOINT_QUEUE',
      'REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH',
      'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','SP_SERVER_DIAGNOSTICS_SLEEP')
  AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;
'@
            'session_summary' = @'
SELECT status, COUNT(*) AS sessions, SUM(cpu_time) AS total_cpu,
       SUM(memory_usage) AS total_mem_pages
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY status;
'@
        }

        $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
        $conn.Open()
        try {
            # (A) Live DMV snapshot: active requests, blocking chains, waits, sessions.
            #     (Requires VIEW SERVER STATE; individual failures are logged, not fatal.)
            foreach ($name in $queries.Keys) {
                try {
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = $queries[$name]
                    $cmd.CommandTimeout = 15
                    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
                    $dt = New-Object System.Data.DataTable
                    [void]$adapter.Fill($dt)
                    $dt | Format-Table -AutoSize -Wrap |
                        Out-File (Join-Path $dirs.Sql "$name.txt") -Encoding UTF8 -Width 4096
                    $dt | Export-Csv (Join-Path $dirs.Sql "$name.csv") -NoTypeInformation
                    Write-Log ("  SQL {0}: {1} rows" -f $name, $dt.Rows.Count)
                } catch {
                    Write-Log ("  SQL query '{0}' failed: {1}" -f $name, $_.Exception.Message) 'WARN'
                }
            }

            # (B) Recent [logging].[tSystemLog] rows from the same database/connection.
            try {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = 'SELECT TOP 1000 * FROM [logging].[tSystemLog] ORDER BY [ID] DESC'
                $cmd.CommandTimeout = 30
                $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
                $dt = New-Object System.Data.DataTable
                [void]$adapter.Fill($dt)
                $dt | Export-Csv (Join-Path $dirs.Sql 'systemlog_top1000.csv') -NoTypeInformation
                # Readable summary: key columns with the message truncated.
                $dt | Select-Object Id, TimeStamp, Level, EventType, SourceContext,
                        @{n='Message';e={ if ($_.Message -and $_.Message.Length -gt 300) { $_.Message.Substring(0,300) + '...' } else { $_.Message } }} |
                    Format-Table -AutoSize -Wrap |
                    Out-File (Join-Path $dirs.Sql 'systemlog_top1000.txt') -Encoding UTF8 -Width 4096
                Write-Log ("  SQL tSystemLog: {0} rows" -f $dt.Rows.Count)
            } catch {
                Write-Log ("  tSystemLog query failed: {0}" -f $_.Exception.Message) 'WARN'
            }
        } finally {
            $conn.Close()
        }
    }
} else {
    Write-Log 'SQL snapshot skipped (-SkipSql set).'
}

# ===========================================================================
# FINALIZE - write step summary and package the ZIP
# ===========================================================================
$overall.Stop()
$script:StepStatus | Format-Table -AutoSize |
    Out-File (Join-Path $stageRoot 'SUMMARY.txt') -Encoding UTF8 -Width 4096
Add-Content (Join-Path $stageRoot 'SUMMARY.txt') "`nTotal collection time: $([math]::Round($overall.Elapsed.TotalSeconds,1)) s"
Write-Log ("All collectors finished in {0:n1}s. Packaging..." -f $overall.Elapsed.TotalSeconds)

# ---------------------------------------------------------------------------
# Package the staging folder one entry at a time so we can report byte-level
# progress (Write-Progress bar + throttled Write-Log) and use a cheaper
# compression level for .dmp files, which dominate size but compress poorly.
# ---------------------------------------------------------------------------
function Compress-StagingFolder {
    param([string]$SourceDir, [string]$DestZip)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $files = Get-ChildItem $SourceDir -Recurse -File
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 1 }
    $totalMB = [math]::Round($totalBytes / 1MB, 1)
    Write-Log ("  packaging {0} files, {1} MB total..." -f $files.Count, $totalMB)

    $fastLevel = [System.IO.Compression.CompressionLevel]::Fastest
    $optLevel  = [System.IO.Compression.CompressionLevel]::Optimal
    $prefixLen = $SourceDir.TrimEnd('\').Length + 1

    $zipStream = [System.IO.File]::Open($DestZip, [System.IO.FileMode]::Create)
    $zip = New-Object System.IO.Compression.ZipArchive(
        $zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $done = 0L; $lastLoggedPct = 0; $i = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($f in $files) {
            $i++
            $rel   = $f.FullName.Substring($prefixLen).Replace('\', '/')
            $level = if ($f.Extension -ieq '.dmp') { $fastLevel } else { $optLevel }

            $entry  = $zip.CreateEntry($rel, $level)
            $entry.LastWriteTime = $f.LastWriteTime
            $eStream = $entry.Open()
            $fStream = [System.IO.File]::OpenRead($f.FullName)
            try { $fStream.CopyTo($eStream) } finally { $fStream.Dispose(); $eStream.Dispose() }

            $done += $f.Length
            $pct = [int](100 * $done / $totalBytes)

            # Update the live bar every file (cheap); log only on 10% milestones.
            $elapsed = $sw.Elapsed.TotalSeconds
            $etaSec  = if ($done -gt 0) { [int]($elapsed / $done * ($totalBytes - $done)) } else { 0 }
            Write-Progress -Activity 'Packaging diagnostics' -PercentComplete $pct `
                -Status ("{0}% - {1:n0}/{2:n0} MB - ETA {3}s - {4}" -f `
                    $pct, ($done/1MB), ($totalBytes/1MB), $etaSec, $rel)

            if ($pct -ge $lastLoggedPct + 10) {
                Write-Log ("  packed {0}% ({1:n0}/{2:n0} MB, file {3}/{4}, ETA {5}s)" -f `
                    $pct, ($done/1MB), ($totalBytes/1MB), $i, $files.Count, $etaSec)
                $lastLoggedPct = $pct
            }
        }
        Write-Progress -Activity 'Packaging diagnostics' -Completed
    } finally {
        $zip.Dispose(); $zipStream.Dispose()
    }
}

try {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-StagingFolder -SourceDir $stageRoot -DestZip $zipPath
    Write-Log "ZIP created: $zipPath"
} catch {
    Write-Log "Per-entry packaging failed ($($_.Exception.Message)); falling back to Compress-Archive" 'WARN'
    Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
}

# Retention: once the new ZIP exists, prune older *-All-Logs-*.zip bundles in the
# output folder (the same pattern and 30-day default as forensics_log_pull.ps1, so
# both tools' bundles in the shared folder get uniform cleanup).
if ($RetentionDays -gt 0 -and (Test-Path $zipPath)) {
    try {
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $old = @(Get-ChildItem -Path $OutputPath -Filter '*-All-Logs-*.zip' -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -ne $zipPath -and $_.LastWriteTime -lt $cutoff })
        foreach ($f in $old) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Log ("Retention: removed {0} (>{1} days old)" -f $f.Name, $RetentionDays)
        }
        if ($old.Count) { Write-Log ("Retention: pruned {0} old ZIP(s) from {1}" -f $old.Count, $OutputPath) }
    } catch {
        Write-Log "Retention cleanup failed: $($_.Exception.Message)" 'WARN'
    }
}

if (-not $KeepStaging) {
    Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Log "Staging retained: $stageRoot"
}

$zipSizeMB = if (Test-Path $zipPath) { [math]::Round((Get-Item $zipPath).Length/1MB,1) } else { 0 }
Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host " Profisee diagnostics collected" -ForegroundColor Green
Write-Host " ZIP : $zipPath ($zipSizeMB MB)" -ForegroundColor Green
Write-Host " Time: $([math]::Round($overall.Elapsed.TotalSeconds,1)) s" -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
