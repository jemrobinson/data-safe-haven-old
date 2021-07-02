# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
# param(
#     [Parameter(Position=0, HelpMessage = "SHM DN")]
#     [string]$shmDn,
#     [Parameter(Position=1, HelpMessage = "Data server hostname")]
#     [string]$dataServerHostname
# )

$targetPath = "OU=Secure Research Environment Data Servers,$shmDn"
Write-Output " [ ] Moving '$dataServerHostname' to '$targetPath'"
Move-ADObject (Get-ADComputer -Identity $dataServerHostname) -TargetPath "$targetPath"
if ($?) {
    Write-Host " [o] Completed"
} else {
    Write-Host " [x] Failed"
}