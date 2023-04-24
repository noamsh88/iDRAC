####################################################################################################################
# Script delete all current virtual disks on phyiscal server using racadm command line tool
####################################################################################################################
# Security Note:
# Script expects to get password value on execution, safe usage options are:
# 1. to execute it with pipeline tool like Jenkins/Azure DevOps Pipelines and use encrypted value on pipeline level
# 2. encrypt idrac_pass string on OS level and set it on external config file
####################################################################################################################

# iDRAC credentials
$idrac_user = $args[0]
$idrac_pass = $args[1]
$idrac_server = $args[2]

# Validation all required variables values
if (!$idrac_user -or !$idrac_pass -or !$idrac_server\) {
  $scriptName = $MyInvocation.MyCommand.Name
  Write-Host "Usage:"
  Write-Host "$scriptName <idrac User> <idrac Pass> <idrac Server> >"
  Write-Host "e.g."
  Write-Host "pwsh $scriptName idrac_user idrac_pass idrac_server "
  exit 1
}

# Validation to exit script if racadm not installed
if (!(Get-Command "racadm" -ErrorAction SilentlyContinue)){
  Write-Host "racadm command line tool NOT FOUND, please install it first and re-run, exiting.."
  exit 1
}

# Get current virtual disks names
$vdisk_names = $(racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage get vdisks --nocertwarn  | Select-String 'Disk.')

foreach($vdisk in $vdisk_names){
  write-host "Deleting $vdisk virtual disk"
  Write-host "racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage deletevd:"$vdisk"" -BackgroundColor DarkMagenta
  racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage deletevd:"$vdisk"

}

# Get RAID Controller Name
[String]$raid_controller = $(racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage get controllers --nocertwarn | Select-String 'RAID')

# Queue iDRAC job to deploy new configuration on server and reboot
racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue create $raid_controller -r forced -s TIME_NOW

# Validate all idrac jobs completed, if not, sleep for 1 min and retry until completed or until timeout
$timeout = New-TimeSpan -Seconds 1800
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
do {
    # Get into list the Percent completed of idrac jobs on server
    $jobs_progress_list = $(racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue view --nocertwarn | Select-String 'Percent Complete=' | awk -F"[" '{print $2}' | awk -F"]" '{print $1}')
    $jobs_progress_list = $($jobs_progress_list | Where-Object {$_}) # remove null values from array

    # Validate all idrac jobs completed, if not finished, sleep for 1 min
    Write-Host "Validating all idrac jobs completed in server.."
    $all_job_completed = $true

    foreach ($job_pct_completed in $jobs_progress_list) { # check if all items in array contain 100 value
        if ($job_pct_completed -ne "100") {
          $all_job_completed = $false
      }
    }

    if ($all_job_completed) {
      Write-Host "All iDRAC jobs completed in server" -BackgroundColor DarkGreen
      break
      }
    else {
      Write-Host "Not all iDRAC jobs completed in server, sleeping for 1 min before next check.."
      Start-Sleep -Seconds 60
      }

    # Timeout validation - exit script in case idrac jobs taking too long (3O min)
    if ($stopwatch.elapsed.TotalSeconds -gt $timeout.TotalSeconds){
      Write-Host "Timeout ERROR: iDRAC Jobs are taking more time than it should ($timeout Minutes), exiting.." -BackgroundColor DarkRed
      Write-Host "Please check iDRAC job status using following CLI:" -BackgroundColor DarkRed
      Write-Host "racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue view" -BackgroundColor DarkRed
      exit 1
    }
} while (($stopwatch.elapsed -lt $timeout))



# Validate there are no remain virtual disks on server
Write-Host "Validating there are no remain virtual disks on $idrac_server server.."
$vdisk_names = $(racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage get vdisks --nocertwarn)

if ($vdisk_names -notcontains 'Disk.'){
    Write-Host "All Virtual Disks removed from $idrac_server server" -BackgroundColor DarkGreen
    exit 0
}
else{
  Write-Host "Not all Virtual Disks removed from $idrac_server server" -BackgroundColor DarkRed
  racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage get vdisks
  exit 1
}
