Set-TransportConfig -AddressBookPolicyRoutingEnabled $true
Set-Mailbox Auto -CustomAttribute1 'Restringido'
Set-Mailbox federicod -CustomAttribute1 "RR"
New-AddressList -Name "AL-Recursos-Restringidos"  -RecipientFilter "((RecipientTypeDetails -eq 'EquipmentMailbox') -and (CustomAttribute1 -eq 'Restringido'))"
New-AddressList -Name "AL-Usuarios-RR" -RecipientFilter "((RecipientTypeDetails -eq 'UserMailbox') -and (CustomAttribute1 -eq 'RR'))"
New-GlobalAddressList -Name "GAL-Restringido" -RecipientFilter "((RecipientTypeDetails -eq 'EquipmentMailbox') -and (CustomAttribute1 -eq 'Restringido'))"
New-AddressBookPolicy -Name "ABP-Restringido" -GlobalAddressList "GAL-Restringido" -OfflineAddressBook "OAB-Restringido" -AddressLists "AL-Recursos-Restringidos" -RoomList "All Rooms"