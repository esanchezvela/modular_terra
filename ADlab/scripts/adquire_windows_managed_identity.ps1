$ResourceGroupName = "rg-domainjoin-automation"
$VMName = "vm-ad-provisioner"

Update-AzVM `
    -ResourceGroupName $ResourceGroupName `
    -VM (Get-AzVM `
        -ResourceGroupName $ResourceGroupName `
        -Name $VMName -Status) `
    -IdentityType SystemAssigned 
`
