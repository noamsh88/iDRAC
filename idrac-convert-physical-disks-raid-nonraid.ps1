####################################################################################################################
# Script converts all host physical disks to RAID or NON-RAID Capable
####################################################################################################################
# Security Note:
# Script expects to get value on run time, usage options are:
# 1. to execute it with pipeline tool like Jenkins/Azure DevOps Pipelines,etc and use encrypted value on pipeline level
# 2. encrypt string on OS level and set idrac_pass varible value on external config file
####################################################################################################################
$idrac_user = $args[0]
$idrac_pass = $args[1]
$idrac_server = $args[2]
$trg_raid_type = $args[3]

# Validation all required variables values
if (!$idrac_user -or !$idrac_pass -or !$idrac_server -or !$trg_raid_type) {
  $scriptName = $MyInvocation.MyCommand.Name
  Write-Host "Usage:"
  Write-Host "$scriptName <idrac User> <idrac Pass> <idrac Server> <Target Physical type RAID Type (RAID/NON-RAID)>"
  exit 1
}

# Validation to exit script if racadm not installed
if (!(Get-Command "racadm" -ErrorAction SilentlyContinue)){
  Write-Host "racadm command line tool NOT FOUND, please install it first and re-run, exiting.."
  exit 1
}

# Set convert operation (RAID or NON-RAID)
if ($trg_raid_type -eq 'RAID'){
  $convert_trg = "converttoraid"
}
elseif ($trg_raid_type -eq 'NON-RAID'){
  $convert_trg = "converttononraid"
}
else{
  Write-Host "wrong or null value set for trg_raid_type variable, please set variable value to RAID or NON-RAID when executing script, exiting.. "
  exit 1
}

# Get list of host physical disks
$pdisk_list = $(racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage get pdisks | Select-String 'Disk.')


# Convert all host physical disks to RAID Capable
foreach ($pdisk in $pdisk_list){
  $convert_pdisk = "$convert_trg" + ":" + "$pdisk"
  Write-Host "Convert $pdisk to $trg_raid_type Capable:"
  Write-Host "racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage $convert_pdisk"
  racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage $convert_pdisk
  sleep 2
}

# Get RAID Controller Name
[String]$raid_controller = $(racadm -r $idrac_server -u $idrac_user -p $idrac_pass storage get controllers | Select-String 'RAID')

# Queue job for new configuration to be deployed and reboot the host
Write-Host "Queue job for new configuration to be deployed and reboot the host"
Write-Host "racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue create $raid_controller -r forced -s TIME_NOW"
racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue create $raid_controller -r forced -s TIME_NOW

sleep 5

# Display job queue status
racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue view

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
      sleep 60
      }

    # Timeout validation - exit script in case idrac jobs taking too long (3O min)
    if ($stopwatch.elapsed.TotalSeconds -gt $timeout.TotalSeconds){
      Write-Host "Timeout ERROR: iDRAC Jobs are taking more time than it should ($timeout Minutes), exiting.." -BackgroundColor DarkRed
      Write-Host "Please check iDRAC job status using following CLI:" -BackgroundColor DarkRed
      Write-Host "racadm -r $idrac_server -u $idrac_user -p $idrac_pass jobqueue view" -BackgroundColor DarkRed
      exit 1
    }
} while (($stopwatch.elapsed -lt $timeout))
