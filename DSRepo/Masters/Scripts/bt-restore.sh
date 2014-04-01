# bt-restore.sh

# This script allows you to restore a Mac HFS+J volume
# from a raw disk image (a special .cdr) or from a
# torrent whose only contents is just such an image.

# It is designed to be used within DeployStudio.

# Started by Clinton Blackmore, 2014-03-13


###########################
# CONFIGURATION VARIABLES #
###########################

# Most parameters are set on the command line but these ones main be changed with care

# Do we wish to verify (and repair, if necessary) the disk after imaging?
REPAIR_DISK=false

# We use a RAM Disk to track information about the torrent's progress
# for scratch space, and to run utilities from
RAMDISK_SIZE_IN_MBs=50	# How large is it, in megabytes?
RAMDISK_NAME="RamDisk"	# What is it called? 

# Pipe Viewer is used for monitoring the progress of raw disk copies.
# It is not needed if you are only doing restores from .torrent files.
# Source at http://www.ivarch.com/programs/pv.shtml
PV=`dirname $0`"/bt-imaging-tools/pv"	# Pipe viewer location

# We create a plist with information about partitions.
# It needs to be stored in an area with R/W access, preferably
# before we create the RAM Disk.
DISK_INFO_FILE="$HOME/Library/DiskInfo"	# Note: no .plist extension here


########################
# FUNCTION DEFINITIONS #
########################

# Parse the command-line arguments, and ensure we have enough information to proceed
# We need to know
# - which partition we are restoring
# - which file we are restoring from
function parse_parameters() {

	# Make sure only root can run our script
	if [[ $EUID -ne 0 ]]; then
		show_error_and_quit_immediately "This script must be run as root to be able to write to disk partitions." 
	fi

	# Check input
	if [ "$#" -lt 2 ]; then

		echo "This utility restores a partition from a special .cdr hard drive image file"
		echo "or a torrent that has one such file in it"
		echo
		echo "Usage: $0 <partition> <image-file-or-torrent>"
		echo "   ex: $0 disk2s1 mypartition.cdr" 
		echo "   ex: $0 '/Volumes/Macintosh HD' mac_hd.cdr.torrent"
		echo
		show_error_and_quit_immediately "Please specify two parameters to this command." 
	fi

	PARTITION_ID="$1"
	if [ "$PARTITION_ID" == "LAST_RESTORED_DEVICE" ]; then
		PARTITION_ID="$DS_LAST_RESTORED_DEVICE"
	fi

	INPUT_FILE_NAME="$2"
}

# Ensure that the disk image we are restoring will fit on the partition we are restoring too!
function check_disk_sizes() {

	show_heading "RESTORE $PARTITION_ID PARTITION FROM $INPUT_FILE_NAME"

	diskutil info -plist "$PARTITION_ID" > "$DISK_INFO_FILE.plist"
	VOLUME_NAME=`defaults read "$DISK_INFO_FILE" VolumeName`
	if [[ "$?" == "1" ]] ; then
		show_error_and_quit_immediately "The volume to restore to can not be found."
	fi 
	TARGET_DEVICE_ID=`defaults read "$DISK_INFO_FILE" DeviceIdentifier`
	ORIGINAL_VOLUME_SIZE=`defaults read "$DISK_INFO_FILE" TotalSize`
	FS_TYPE=`defaults read "$DISK_INFO_FILE" FilesystemName`

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
			diskutil info -plist "$INPUT_FILE_NAME" > "$DISK_INFO_FILE.plist"
			INPUT_DEVICE_ID=`defaults read "$DISK_INFO_FILE" DeviceIdentifier`
			if [[ "$?" == "1" ]] ; then
				show_error_and_quit_immediately "The input file is not a torrent, disk image file or partition.  Aborting." 
			fi 
			INPUT_FILE_NAME="/dev/r${INPUT_DEVICE_ID}"
			DATA_SIZE=`defaults read "$DISK_INFO_FILE" TotalSize`
		fi
	fi

	printf "Data file size: % '20d bytes. " "$DATA_SIZE"

	if [ "$ORIGINAL_VOLUME_SIZE" -lt "$DATA_SIZE" ] ; then
		show_error_and_quit_immediately "The data source is too large to restore to the specified volume." 
	else
		echo "The data will fit."
	fi 

	# Ask the user if they'd like to proceed.
	# Note that when run non-interactively, it defaults to proceeding.
	echo
	echo "Do you wish to erase this partition?"
	select yn in "Yes" "No"; do
		case $yn in
			Yes ) break;;
			No )  exit;;
		esac
	done

}

function create_ramdisk_and_symlinks() {
	
	show_heading "CREATING RAMDISK"
	diskutil erasevolume HFS+ "$RAMDISK_NAME" `hdiutil attach -nomount ram://$((RAMDISK_SIZE_IN_MBs * 1024 * 1024 / 512))`
	if [[ ! -e "/Volumes/$RAMDISK_NAME" ]] ; then
		show_error_and_quit_immediately "Error: Unable to create RAM Disk. Aborting."
	fi
	
	# Now that we have the Ram Disk, create some folders and symlinks for Transmission
	mkdir -p "/Volumes/$RAMDISK_NAME/Library/Application Support"
	mkdir -p "$HOME/Library/Application Support"	
	mkdir -p "/Volumes/$RAMDISK_NAME/Downloads"
	
	for FOLDER in transmission-daemon Transmission ; do
		mkdir "/Volumes/$RAMDISK_NAME/Library/Application Support/$FOLDER"
		ln -s "/Volumes/$RAMDISK_NAME/Library/Application Support/$FOLDER" "$HOME/Library/Application Support/$FOLDER"
	done
}

# Destructively shrink the target partition to match the size of the input data
shrink_partition {
	SHRINK_START=$(timer)
	show_heading "ERASING PARTITION $TARGET_DRIVE_ID"

	diskutil splitPartition $TARGET_DEVICE_ID 1 "jhfs+" "Target Volume" ${DATA_SIZE}b

	# Check that the volume size now matches the torrent's size
	diskutil info -plist "$TARGET_DEVICE_ID" > "$DISK_INFO_FILE.plist"
	NEW_VOLUME_SIZE=`defaults read "$DISK_INFO_FILE" TotalSize`

	if [ "$NEW_VOLUME_SIZE" -ne "$DATA_SIZE" ] ; then

		echo
		show_warning "Unable to resize the volume to match the torrent's contents exactly."
		echo
		printf "   New Partition size: % '20d bytes.\n" "$NEW_VOLUME_SIZE"
		printf "       Data file size: % '20d bytes.\n " "$DATA_SIZE"
		printf "           Difference: % '19d bytes.\n" $(expr $NEW_VOLUME_SIZE - $DATA_SIZE)
		echo
		echo "Volume header will require a repair afterwards"
		REPAIR_DISK=true
		echo
	fi 
	show_elapsed_time "Time to shrink partition: " "$SHRINK_START"
}

# Actually write the disk image to the disk partition
# via bittorrent or dd
restore_from_file {
	show_heading "IMAGING PARTITION $TARGET_DRIVE_ID"
	IMAGING_START=$(timer)

	diskutil umount $TARGET_DEVICE_ID

	# I think 'raw' devices work better, but you can choose either
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
}

repair_partition {
	REPAIR_START=$(timer)
	show_heading "REPAIRING PARTITION $TARGET_DRIVE_ID"
	diskutil repairVolume $TARGET_DEVICE_ID
	show_elapsed_time "Time to repair partition: " "$REPAIR_START"
}

# Non-destructively resize the disk back to its original size
enlarge_partition {
	show_heading "EXPANDING PARTITION $TARGET_DRIVE_ID"
	EXPAND_START=$(timer)

	diskutil resizeVolume $TARGET_DEVICE_ID ${ORIGINAL_VOLUME_SIZE}b

	# For interest sake, let's get the volume's size one final time
	diskutil info -plist "$TARGET_DEVICE_ID" > "$DISK_INFO_FILE.plist"
	FINAL_VOLUME_SIZE=`defaults read "$DISK_INFO_FILE" TotalSize`

	if [ "$FINAL_VOLUME_SIZE" -ne "$ORIGINAL_VOLUME_SIZE" ] ; then
		printf "Strange.  The final volume size is % '20d bytes\n" "$FINAL_VOLUME_SIZE"
		printf "but it was originally              % '20d bytes\n" "$ORIGINAL_VOLUME_SIZE"
	else
		printf "Volume expanded to its original size of % '20d bytes\n" "$ORIGINAL_VOLUME_SIZE"
	fi

	show_elapsed_time "Time to expand partition: " "$EXPAND_START"
}

# Cleans up the RAM Disk
function cleanup()
{
	# checks for a ram disk and destroys it
	# no parameters expected
	
	show_heading "CLEANING UP RAMDISK"
	hdiutil eject /Volumes/ramdisk/
}


function run_torrent() {
	# Actually runs the torrent program, using the torrent file specified in $1
	
	# Possible optimization: copy transmission applications to RAM disk

	# Set preferences
	mkdir -p ~/Library/Preferences
	cp "`dirname $0`/org.m0k.transmission.plist" ~/Library/Preferences/
	cp "`dirname $0`/org.m0k.transmission.plist" "$OLD_HOME/Library/Preferences/"

	#launchctl setenv HOME "$HOME"  

	# Here we'll spawn the Transmission (Cocoa) GUI application
	"`dirname $0`/Transmission.app/Contents/MacOS/Transmission" &
	#"`dirname $0`/transmission-daemon" 

	local TRREMOTE="`dirname $0`/transmission-remote"

	# wait until service is running
	echo "Waiting for transmission RPC service to be ready"
	while [ "1" -eq `$TRREMOTE -l 2>&1 | grep -c "Couldn't connect to server"` ] ; do
		echo .
		sleep 2
	done
	
	# Download the torrent
	echo "Downloading Torrent"
	"$TRREMOTE"  --download-dir "$HOME/Downloads" --add "$1"
	
	# Monitor the download
	while : ; do
		# The result is on the second line of the output
		local result=`"$TRREMOTE" -t 1 --list | head -n 2 | tail -n 1`
		echo $result	# let user watching logs see progress
		# Have we finished downloading it?
		if [ `echo $result | grep -e "100%.*Done" -c` -eq "1" ] ; then
			break;
		fi
		sleep 15
	done
	
	# Allow it to seed for 30 more seconds
	echo "Torrent is done.  Seeding for 30 more seconds"
	sleep 30
	"$TRREMOTE" -t 1 --remove
	
	# Kill the transmission GUI (or daemon)
	sleep 5
	killall Transmission
	killall transmission-daemon
}

function cleanup_after_torrent() {
	# Deletes the folder where transmission remembers how far it go with this torrent
	# TODO: Test that this is right
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

# Expects a string parameter, which is then displayed before quitting
function show_error_and_quit_immediately()
{
	echo "RuntimeAbortWorkflow: $1" 1>&2
	exit 1	
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


################
# MAIN PROGRAM #
################

SCRIPT_START=$(timer)

parse_parameters
check_disk_sizes
create_ramdisk_and_symlinks
shrink_partition
restore_from_file
if [ "$REPAIR_DISK" == true ]; then
	repair_partition
fi
enlarge_partition
destroy_ramdisk

echo
show_elapsed_time "DONE. Total time: " "$SCRIPT_START"

exit 0