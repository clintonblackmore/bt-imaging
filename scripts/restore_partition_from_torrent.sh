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


# Utility programs and settings
# Replace these variables or functions with things appropriate for the applications you are using

USE_RAMDISK=true
RAMDISK_SIZE_IN_MBs=50

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

if which -s tput ; then
	has_tput=true
else
	has_tput=false
fi

function show_heading()
{
	# pass one parameter, the value you wish displayed as a heading

	echo
	if [ "$has_tput" == true ]; then
		echo `tput bold`"$1"`tput sgr0`
	else
		echo "$1"
	fi
	
	# print out a bar with as many characters as in the title
	printf '%*s\n' ${#1} '' | tr ' ' '='
}

function show_warning() 
{
	# pass one parameter for the warning to display	
	if [ "$has_tput" == true ]; then
		echo `tput setaf`"$1"`tput sgr0`
	else
		echo "WARNING: $1"
	fi
}

function show_elapsed_time()
{
	# Outputs the time it took to do something
	# $1 = message to prepend
	# $2 = name of the timer
	# $3 = message to append
	#
	# ex: show_elapsed_time "It took " "$EXPAND_START" " seconds"
	# would show something like: "It took __10__ seconds"
	
	if [ "$has_tput" == true ]; then
		echo "$1"`tput smul`"$(timer $2)"`tput sgr0`"$3"
	else
		echo "$1__$(timer $2)__$3"
	fi
}

function cleanup_ramdisk()
{
	# checks for a ram disk and destroys it
	# no parameters expected
	
	if [ "$USE_RAMDISK" == true ]; then
		show_heading "CLEANING UP RAMDISK"
		popd
		HOME="$OLD_HOME"
		hdiutil eject /Volumes/ramdisk/
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


if [ "$USE_RAMDISK" == true ]; then
	show_heading "CREATING RAMDISK"
	diskutil erasevolume HFS+ "ramdisk" `hdiutil attach -nomount ram://$((RAMDISK_SIZE_IN_MBs * 1024 * 1024 / 512))`
	if [[ ! -e /Volumes/ramdisk ]] ; then
		echo "Error: Unable to create RAM Disk."
		exit 3
	fi
	
	OLD_HOME="$HOME"
	export HOME="/Volumes/ramdisk"
	
	# Folders for use by Transmission
	mkdir -p "$HOME/Library/Application Support"
	mkdir -p "$HOME/Downloads"
	pushd /Volumes/ramdisk
fi

show_heading "RESTORE $PARTITION_ID PARTITION FROM $INPUT_FILE_NAME"

# Get some info about the partition
diskutil info -plist "$PARTITION_ID" > info.plist
VOLUME_NAME=`defaults read "$PWD/info" VolumeName`
if [[ "$?" == "1" ]] ; then
	echo "Error: either the selected volume can not be found"
	echo "or this script does not have permission to write to a file with drive information"
	exit 2
fi 
TARGET_DEVICE_ID=`defaults read "$PWD/info" DeviceIdentifier`
ORIGINAL_VOLUME_SIZE=`defaults read "$PWD/info" TotalSize`
FS_TYPE=`defaults read "$PWD/info" FilesystemName`

#echo "The '$VOLUME_NAME' partition (/dev/$TARGET_DEVICE_ID) is a $ORIGINAL_VOLUME_SIZE byte $FS_TYPE partition."

printf "Partition size: % '20d bytes; dev: $TARGET_DEVICE_ID; name: $VOLUME_NAME type: $FS_TYPE\n" "$ORIGINAL_VOLUME_SIZE"
    

# Get some information about the file we are restoring from
if [[ "$INPUT_FILE_NAME" == *torrent ]] ; then
	DATA_SIZE=`grep -aPo ':lengthi\K[0-9]*' "$INPUT_FILE_NAME"`
else
	if [[ -f "$INPUT_FILE_NAME" ]] ; then
		# We will copy from a regular file
		DATA_SIZE=`stat -f "%z" "$INPUT_FILE_NAME"`
	else
		# Perhaps we are copying from another partition
		diskutil info -plist "$INPUT_FILE_NAME" > info.plist
		INPUT_DEVICE_ID=`defaults read "$PWD/info" DeviceIdentifier`
		if [[ "$?" == "1" ]] ; then
			echo "The input for 'dd' is not a regular file"
			echo "and is not another partition.  Aborting."
			exit 6
		fi 
		INPUT_FILE_NAME="/dev/r${INPUT_DEVICE_ID}"
		DATA_SIZE=`defaults read "$PWD/info" TotalSize`
	fi
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
        No ) cleanup_ramdisk ; exit;;
    esac
done

SHRINK_START=$(timer)
show_heading "ERASING PARTITION $TARGET_DRIVE_ID"

diskutil splitPartition $TARGET_DEVICE_ID 1 "jhfs+" "Target Volume" ${DATA_SIZE}b

# Check that the volume size now matches the torrent's size
diskutil info -plist "$TARGET_DEVICE_ID" > info.plist
NEW_VOLUME_SIZE=`defaults read "$PWD/info" TotalSize`

if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then

	echo
	show_warning "Unable to resize the volume to match the torrent's contents exactly."
	echo
	printf "   New Partition size: % '20d bytes.\n" "$NEW_VOLUME_SIZE"
	printf "       Data file size: % '20d bytes.\n " "$DATA_SIZE"
    printf "           Difference: % '19d bytes.\n" $(expr $NEW_VOLUME_SIZE - $DATA_SIZE)
	echo
	echo "Volume header will require a repair afterwards"
	echo
fi 
show_elapsed_time "Time to shrink partition: " "$SHRINK_START"

IMAGING_START=$(timer)
show_heading "IMAGING PARTITION $TARGET_DRIVE_ID"

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
	#dd if="$INPUT_FILE_NAME" bs=1m | "$PV" -s $DATA_SIZE | dd of=$OUTPUT_DEVICE_NAME bs=1m
	# dd without pipe viewer
	#dd if="$INPUT_FILE_NAME" of=$OUTPUT_DEVICE_NAME bs=1m
	
	# Turns out Pipe Viewer doesn't event need 'dd'
	"$PV" -n -s $DATA_SIZE "$INPUT_FILE_NAME" 2>&1  > "$OUTPUT_DEVICE_NAME" | while read PERCENT_DONE ; do
		echo "Progress: $PERCENT_DONE"
	done

	EXIT_STATUS=$?
fi

echo "Done imaging.  Exit status = $EXIT_STATUS"
show_elapsed_time "Time to image partition: " "$IMAGING_START"

VERIFY_START=$(timer)
show_heading "VERIFYING PARTITION $TARGET_DRIVE_ID"

#if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then
#	echo
#	echo "Repairing volume header"
	diskutil verifyVolume $TARGET_DEVICE_ID
	EXIT_STATUS=$?
#fi 

echo "Done verifying.  Exit status = $EXIT_STATUS"
show_elapsed_time "Time to verify partition: " "$VERIFY_START"

REPAIR_START=$(timer)
show_heading "REPAIRING PARTITION $TARGET_DRIVE_ID"

#if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then
#	echo
#	echo "Repairing volume header"
	diskutil repairVolume $TARGET_DEVICE_ID
#fi 

show_elapsed_time "Time to repair partition: " "$REPAIR_START"

EXPAND_START=$(timer)
show_heading "EXPANDING PARTITION $TARGET_DRIVE_ID"

diskutil resizeVolume $TARGET_DEVICE_ID ${ORIGINAL_VOLUME_SIZE}b

# For interest sake, let's get the volume's size one final time
diskutil info -plist "$TARGET_DEVICE_ID" > info.plist
FINAL_VOLUME_SIZE=`defaults read "$PWD/info" TotalSize`

if [ "$FINAL_VOLUME_SIZE" -ne "$ORIGINAL_VOLUME_SIZE" ] ; then
	printf "Strange.  The final volume size is % '20d bytes\n" "$FINAL_VOLUME_SIZE"
	printf "but it was originally              % '20d bytes\n" "$ORIGINAL_VOLUME_SIZE"
else
	printf "Volume expanded to its original size of % '20d bytes\n" "$ORIGINAL_VOLUME_SIZE"
fi

show_elapsed_time "Time to expand partition: " "$EXPAND_START"

rm info.plist

cleanup_ramdisk

echo
show_elapsed_time "DONE. Total time: " "$SCRIPT_START"
