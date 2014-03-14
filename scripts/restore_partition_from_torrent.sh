# restore_partition_from_torrent.sh

# This script takes a partition to replace and a .torrent file,
# destroys the partition, creates a new one the size of the torrent,
# downloads the torrent, resizes the partition to its original size
# and leaves you with a nicely restored filesystem.

# Started by Clinton Blackmore, 2014-03-13



# Timer code courtesy of Mitch Frazier
# http://www.linuxjournal.com/content/use-date-command-measure-elapsed-time
#####################################################################
# If called with no arguments a new timer is returned.
# If called with arguments the first is used as a timer
# value and the elapsed time is returned in the form HH:MM:SS.
#
function timer()
{
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local  stime=$1
        etime=$(date '+%s')

        if [[ -z "$stime" ]]; then stime=$etime; fi

        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%d:%02d:%02d' $dh $dm $ds
    fi
}


if [ "$#" -ne 2 ]; then
	echo "This utility restores a partition from a torrent of the partition."
    echo "Usage: $0 partition torrent"
    echo "   ex: $0 disk2s1 mypartition.torrent" 
    echo "   ex: $0 '/Volumes/Macintosh HD' mac_hd.torrent"
    exit 1
fi

TIMER=$(timer)

PART_ID="$1"
TORRENT="$2"
CONTENTS_NAME=`echo $TORRENT | rev | cut -d "." -f 2- | cut -d "/" -f 1 | rev`

TORRENT_SIZE=`grep -aPo ':lengthi\K[0-9]*' "$TORRENT"`

rm -r "/Users/sysadmin/Library/Application Support/transmission"

# Get some info about the partition
diskutil info -plist "$PART_ID" > info.plist
VOLUME_NAME=`defaults read $PWD/info VolumeName`
DEVICE_ID=`defaults read $PWD/info DeviceIdentifier`
ORIGINAL_VOLUME_SIZE=`defaults read $PWD/info TotalSize`
FS_TYPE=`defaults read $PWD/info FilesystemUserVisibleName`

echo "The '$VOLUME_NAME' partition (/dev/$DEVICE_ID) is a $ORIGINAL_VOLUME_SIZE byte $FS_TYPE partition."

if [ "$ORIGINAL_VOLUME_SIZE" -le "$TORRENT_SIZE" ] ; then
	echo "The torrent is $TORRENT_SIZE and will not fit on this volume."
	exit 2
fi 

echo "The partition in the torrent to restore is $TORRENT_SIZE bytes, and will fit."

echo "Do you wish to erase this partition?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done

echo "Erasing"

echo diskutil splitPartition $DEVICE_ID 1 "jhfs+" "Target Volume" ${TORRENT_SIZE}b
diskutil splitPartition $DEVICE_ID 1 "jhfs+" "Target Volume" ${TORRENT_SIZE}b

# Check that the volume size now matches the torrent's size
diskutil info -plist "$DEVICE_ID" > info.plist
NEW_VOLUME_SIZE=`defaults read $PWD/info TotalSize`

if [ "$NEW_VOLUME_SIZE" -ne "$TORRENT_SIZE" ] ; then
	echo "Unable to resize the volume to match the torrent's contents exactly."
	echo "The volume size is now $NEW_VOLUME_SIZE bytes, but the torrent is $TORRENT_SIZE".
	echo "Volume header will require a repair afterwards"
fi 


echo "TORRENT"
echo

#ln -s "/dev/${DEVICE_ID}" ~/Downloads/"${CONTENTS_NAME}" 
ln -s "/dev/r${DEVICE_ID}" ~/Downloads/"${CONTENTS_NAME}" 
diskutil umount $DEVICE_ID
~/Desktop/transmissioncli -f /Users/sysadmin/Documents/kill_torrent_after_seeding_for_30s.sh "$TORRENT"

echo
echo "DONE TORRENT"

if [ "$NEW_VOLUME_SIZE" -ne "$TORRENT_SIZE" ] ; then
	echo
	echo "Repairing volume header"
	diskutil repairVolume $DEVICE_ID
fi 

echo
echo "Expanding volume to original size"

diskutil resizeVolume $DEVICE_ID ${ORIGINAL_VOLUME_SIZE}b

# For interest sake, let's get the volume's size one final time
diskutil info -plist "$DEVICE_ID" > info.plist
FINAL_VOLUME_SIZE=`defaults read $PWD/info TotalSize`

if [ "$FINAL_VOLUME_SIZE" -ne "$ORIGINAL_VOLUME_SIZE" ] ; then
	echo "Strange.  The final volume size is $FINAL_VOLUME_SIZE,"
	echo "but it was originally $ORIGINAL_VOLUME_SIZE."
else
	echo "Volume expanded to its original size of $ORIGINAL_VOLUME_SIZE."
fi

# Delete symlink
rm ~/Downloads/"${CONTENTS_NAME}"


echo "DONE"
echo "Elapsed time: $(timer $TIMER)"

