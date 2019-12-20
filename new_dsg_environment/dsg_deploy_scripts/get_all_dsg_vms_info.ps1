

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;

$dsgSubs = (Get-AzSubscription | Where-Object {$_.name -like "Turing DSG*"})

foreach ( $sub in $dsgSubs) {
    $_ = Set-AzContext -Subscription $sub.Name
    write-host $sub.Name
    get-azvm -Status | Select-Object Name, HardwareProfile.VmSize, Powerstate
    write-host "`n"
}

Set-AzContext $prevContext