# restore_partition_from_torrent.sh

# This script aims to be an alternative to using ASR to
# restore a Mac jhfs+ partition.

# This script takes a partition to operate on and a file.
# The file may be a raw hard drive image (a special .cdr)
# or a torrent file that contains just such an image.
# This tool destroys the specified partition and creates a new
# one in its place just the right size for the image file.
# It then lays down the image file (using 'dd' or a bittorrent 
# program), and lastly resizes the partition back to its 
# original size, hopefully leaving you with a nicely
# restored filesystem.

# Started by Clinton Blackmore, 2014-03-13


# Utility programs
# Replace these variables or functions with things appropriate for the applications you are using

# Pipe viewer, perfect for knowing how 'dd' is doing.  Source at http://www.ivarch.com/programs/pv.shtml
PV=`dirname $0`"/pv"	

function run_torrent() {
	# Actually runs the torrent program, using the torrent file specified in $1
	# Here I've told it to use transmission 2.82 command-line interface utility,
	# and to kill it 30 seconds after completion
	"`dirname $0`/transmissioncli" -f "`dirname $0`/kill_torrent_after_seeding_for_30s.sh" "$1"
	# Note: we check the return status here, so don't add anything after this
}

function cleanup_after_torrent() {
	# Deletes the folder where transmission remembers how far it go with this torrent
	rm -r ${HOME}/Library/Application\ Support/transmission
}

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


###################
# Start of script #
###################

# Check input
if [ "$#" -lt 2 ]; then

	echo "This utility restores a partition from a special .cdr hard drive image file"
	echo "or a torrent that has one such file in it"
	echo
    echo "Usage: $0 <partition> <image-file-or-torrent>"
    echo "   ex: $0 disk2s1 mypartition.cdr" 
    echo "   ex: $0 '/Volumes/Macintosh HD' mac_hd.cdr.torrent"
    exit 1
fi


# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to be able to write to disk partitions." 1>&2
   exit 1
fi


SCRIPT_START=$(timer)

PARTITION_ID="$1"
INPUT_FILE_NAME="$2"

echo
echo `tput bold`"RESTORE $PARTITION_ID PARTITION FROM $INPUT_FILE_NAME"`tput sgr0`



# Get some info about the partition
diskutil info -plist "$PARTITION_ID" > info.plist
VOLUME_NAME=`defaults read $PWD/info VolumeName`
TARGET_DEVICE_ID=`defaults read $PWD/info DeviceIdentifier`
ORIGINAL_VOLUME_SIZE=`defaults read $PWD/info TotalSize`
FS_TYPE=`defaults read $PWD/info FilesystemName`

#echo "The '$VOLUME_NAME' partition (/dev/$TARGET_DEVICE_ID) is a $ORIGINAL_VOLUME_SIZE byte $FS_TYPE partition."

printf "Partition size: % '20d bytes; dev: $TARGET_DEVICE_ID; name: $VOLUME_NAME type: $FS_TYPE\n" "$ORIGINAL_VOLUME_SIZE"
    

# Get some information about the file we are restoring from
if [[ $INPUT_FILE_NAME == *torrent ]] ; then
	DATA_SIZE=`grep -aPo ':lengthi\K[0-9]*' "$INPUT_FILE_NAME"`
else
	DATA_SIZE=`stat -f "%z" "$INPUT_FILE_NAME"`
fi

printf "Data file size: % '20d bytes. " "$DATA_SIZE"


if [ "$ORIGINAL_VOLUME_SIZE" -le "$DATA_SIZE" ] ; then
	echo "The data will not fit on this volume."
	exit 2
else
	echo "The data will fit."
fi 

echo
echo "Do you wish to erase this partition?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done

SHRINK_START=$(timer)
echo
echo `tput bold`"ERASING PARTITION $TARGET_DRIVE_ID"`tput sgr0`

diskutil splitPartition $TARGET_DEVICE_ID 1 "jhfs+" "Target Volume" ${DATA_SIZE}b

# Check that the volume size now matches the torrent's size
diskutil info -plist "$TARGET_DEVICE_ID" > info.plist
NEW_VOLUME_SIZE=`defaults read $PWD/info TotalSize`

if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then

	echo
	echo `tput setaf 1`"Unable to resize the volume to match the torrent's contents exactly."`tput sgr0`
	echo
	printf "   New Partition size: % '20d bytes.\n" "$NEW_VOLUME_SIZE"
	printf "       Data file size: % '20d bytes.\n " "$DATA_SIZE"
    printf "           Difference: % '19d bytes.\n" $(expr $NEW_VOLUME_SIZE - $DATA_SIZE)
	echo
	echo "Volume header will require a repair afterwards"
	echo
fi 
echo "Time to shrink partition: " `tput smul` " $(timer $SHRINK_START)" `tput rmul`


IMAGING_START=$(timer)
echo
echo `tput bold`"IMAGING PARTITION $TARGET_DRIVE_ID"`tput sgr0`

diskutil umount $TARGET_DEVICE_ID

#OUTPUT_DEVICE_NAME="/dev/${TARGET_DEVICE_ID}"
OUTPUT_DEVICE_NAME="/dev/r${TARGET_DEVICE_ID}"

if [[ $INPUT_FILE_NAME == *torrent ]] ; then

	# Create a symlink to the partition we want to restore on
	CONTENTS_NAME=`echo $INPUT_FILE_NAME | rev | cut -d "." -f 2- | cut -d "/" -f 1 | rev`
	echo "Symlinking ~/Downloads/${CONTENTS_NAME} to $OUTPUT_DEVICE_NAME"
	ln -s $OUTPUT_DEVICE_NAME ~/Downloads/"${CONTENTS_NAME}" 

	# Write the data blocks using bittorrent!
	run_torrent "$INPUT_FILE_NAME"
	EXIT_STATUS=$?		# Hmm... This doesn't seem so helpful here.
	cleanup_after_torrent

	# Delete symlink
	rm ~/Downloads/"${CONTENTS_NAME}"

else
	
	# Run 'dd', using the pipe viewer to see the progress
	dd if="$INPUT_FILE_NAME" bs=1m | "$PV" -s $DATA_SIZE | dd of=$OUTPUT_DEVICE_NAME bs=1m
	#dd if="$INPUT_FILE_NAME" of=$OUTPUT_DEVICE_NAME bs=1m
	
	EXIT_STATUS=$?
fi

echo "Done imaging.  Exit status = $EXIT_STATUS"
echo "Time to image partition: " `tput smul` " $(timer $IMAGING_START)" `tput rmul`


VERIFY_START=$(timer)
echo
echo `tput bold`"VERIFYING PARTITION $TARGET_DRIVE_ID"`tput sgr0`

#if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then
#	echo
#	echo "Repairing volume header"
	diskutil verifyVolume $TARGET_DEVICE_ID
	EXIT_STATUS=$?
#fi 

echo "Done verifying.  Exit status = $EXIT_STATUS"
echo "Time to verify partition: " `tput smul` " $(timer $VERIFY_START)" `tput rmul`


REPAIR_START=$(timer)
echo
echo `tput bold`"REPAIRING PARTITION $TARGET_DRIVE_ID"`tput sgr0`

#if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then
#	echo
#	echo "Repairing volume header"
	diskutil repairVolume $TARGET_DEVICE_ID
#fi 

echo "Time to repair partition: " `tput smul` " $(timer $REPAIR_START)" `tput rmul`

EXPAND_START=$(timer)
echo
echo `tput bold`"EXPANDING PARTITION $TARGET_DRIVE_ID"`tput sgr0`

diskutil resizeVolume $TARGET_DEVICE_ID ${ORIGINAL_VOLUME_SIZE}b

# For interest sake, let's get the volume's size one final time
diskutil info -plist "$TARGET_DEVICE_ID" > info.plist
FINAL_VOLUME_SIZE=`defaults read $PWD/info TotalSize`

if [ "$FINAL_VOLUME_SIZE" -ne "$ORIGINAL_VOLUME_SIZE" ] ; then
	echo "Strange.  The final volume size is $FINAL_VOLUME_SIZE,"
	echo "but it was originally $ORIGINAL_VOLUME_SIZE."
else
	echo "Volume expanded to its original size of $ORIGINAL_VOLUME_SIZE."
fi

echo "Time to expand partition: " `tput smul` " $(timer $EXPAND_START)" `tput rmul`


rm info.plist

echo
echo "DONE. Total time: " `tput smul` " $(timer $SCRIPT_START)" `tput rmul`

