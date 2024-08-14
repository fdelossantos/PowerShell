#Provide the subscription Id of the subscription where managed disk is created
$subscriptionId = "00000000-0000-0000-0000-000000000000"

#Provide the name of your resource group where managed is created
$resourceGroupName ="My-RG"

#Provide the managed disk name 
$diskName = "MyDiskName"

#Provide Shared Access Signature (SAS) expiry duration in seconds e.g. 3600.
#Know more about SAS here: https://docs.microsoft.com/en-us/Az.Storage/storage-dotnet-shared-access-signature-part-1
$sasExpiryDuration = "3600"

#Provide storage account name where you want to copy the underlying VHD of the managed disk. 
$storageAccountName = "vmcoolstorage"

#Name of the storage container where the downloaded VHD will be stored
$storageContainerName = "temporal"

#Provide the key of the storage account where you want to copy the VHD of the managed disk. 
$storageAccountKey = '_____=='

#Provide the name of the destination VHD file to which the VHD of the managed disk will be copied.
$destinationVHDFileName = "disk.snapshot"

#Set the value to 1 to use AzCopy tool to download the data. This is the recommended option for faster copy.
#Download AzCopy v10 from the link here: https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10
#Ensure that AzCopy is downloaded in the same folder as this file
#If you set the value to 0 then Start-AzStorageBlobCopy will be used. Azure storage will asynchronously copy the data. 
$useAzCopy = 0

Connect-AzAccount

# Set the context to the subscription Id where managed disk is created
Select-AzSubscription -SubscriptionId $SubscriptionId

#Generate the SAS for the managed disk 
$sas = Grant-AzDiskAccess -ResourceGroupName $ResourceGroupName -SnapshotName $diskName -DurationInSecond $sasExpiryDuration -Access Read

#Create the context of the storage account where the underlying VHD of the managed disk will be copied
$destinationContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

#Copy the VHD of the managed disk to the storage account
if($useAzCopy -eq 1)
{
    $containerSASURI = New-AzStorageContainerSASToken -Context $destinationContext -ExpiryTime(get-date).AddSeconds($sasExpiryDuration) -FullUri -Name $storageContainerName -Permission rw
    azcopy copy $sas.AccessSAS $containerSASURI

}
else
{
    Start-AzStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $destinationVHDFileName
}

$resourceGroupName ="Other-RG"

$diskName = "Snapshot1"
$destinationVHDFileName = "$diskName.snapshot"
$sas = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $diskName -DurationInSecond $sasExpiryDuration -Access Read
Start-AzStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $destinationVHDFileName

$diskName = "Snapshot2"
$destinationVHDFileName = "$diskName.snapshot"
$sas = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $diskName -DurationInSecond $sasExpiryDuration -Access Read
Start-AzStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $destinationVHDFileName

# https://stackoverflow.com/questions/12851764/how-to-convert-exist-block-blob-to-pageblob#:~:text=Having%20that%2C%20open%20the%20Cloud%20Shell%20and%20write,After%20coping%2C%20just%20delete%20the%20old%20page%20blobs.
.\azcopy.exe copy "$SASUrlOrigen" "$SASUrlDestino" --recursive --blob-type=BlockBlob