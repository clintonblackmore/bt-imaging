Overview
=======

bt-imaging is a work-in-progress set of tools to allow you to image Mac computers using BitTorrent (or `dd`).  It is being developed on Mac OS X 10.7, and may work on 10.6 or even 10.5, and should work on newer versions, too.


Here is how the bt-imaging tools work.

1. You create a special raw-block image that you wish to deploy.

2. Optionally, serve the file up using BitTorrent.

3. Tell the script which partition will be imaged.

4. Tell the script where the data comes from -- either from the special image file or from a torrent containing such a file.

5. The partition is destroyed and replaced with one exactly the size of the raw-block data.

6. The partition is then resized back to what it was initially.

7. Profit!


Scroll down for further details and for information about third-party tools.
To see a 'screenshot', as it were, check out the file "sample output.txt"

1. Creating the special raw-block image.
------------

This way works for sure:

- Create or otherwise set up a journaled HFS+ filesystem (the standard Mac OS X filesystem) on a partition.
- Optionally shrink the partition as small as possible (perhaps using the Disk Utility GUI).
- Identify your partition's device name.  
	- either run `diskutil list` and look for it
	- or use the Disk Utility GUI, select your partition, go Cmd-I, and look at the disk identifier
	- the answer will be something like `disk0s4`.  We will use it as `/dev/rdisk0s4` is the next step.
- Create a raw block image, exactly as many bytes are your partition is large, using one of these two commands
   - `hdiutil create -srcdevice /dev/rdisk0s4 -format UDTO -layout NONE partition.udto`
   - or: `sudo dd if=/dev/rdisk0s4 of=partition.dd bs=1m`
   - these will create files named 'partition.udto.cdr' and 'partition.dd' respectively.  They are identical.
   - (note that `dd` gives you no progress report; it works away silently for several minutes until it is done.)

Note that it should be possible to create a disk image from a folder (like /Volumes/My Gold Master or /Applications).  This is as close as I've come:

   `hdiutil create -srcfolder "/Volumes/My Gold Master" -format UDTO -layout NONE -fs "HFS+J" goldmaster`

This creates a beautiful, minimally-sized, raw file.  It even restores using my script.  However, even though you can mount the result, disk utility says it doesn't verify and can't repair it most of the time.  I believe this is because the size is not a multiple of 4K, and filesystems on disk use 4K sectors.  I've tried playing with -align and such but haven't gotten it yet.  I do believe that specifying a size (using say -megabytes) works, but I don't know how to determine what size it should be so as to have little wasted space.


2. Optionally serve it up using BitTorrent.
---------------

I am by no means a BitTorrent master; I had to dig in to learn how to use it.  I expect that some of you will have better ideas on how to tweak it.

Here is some really brief BitTorrent terminology.  BitTorrent transmits large files over the internet.  It breaks them up into pieces and your client gets pieces from other sources that have the pieces.  The service managing the operation is called the tracker.  The clients are called peers, as they are sharing the file pieces back and forth, and any client with all the pieces is called a seed.  A torrent file contains metadata about where the tracker is, how large the file is, how many pieces there are, and what the checksums for each piece is so you can tell if you've gotten it right or not.

### Setting Up A Tracker

So, we'll need a tracker.  I'm using [Vuze](http://www.vuze.com/) (5.3.0.0). as it contains a built-in tracker, and is thus easy to use, and that is what these instructions will use.

If you'd like to use Vuze too, download it and install it, reading the options carefully and declining the crapware it would like to install.

Start it up.  Go to `Vuze -> Preferences`, and change the `Mode` from `Beginner` to `Intermediate`.  Also in the preferences, go to `Tracker -> Server` in the left column, and set an IP for your server (I used `localhost` in my test setup), and enable a tracker on an HTTP port (the default is fine).  Save and quit the preferences.

Now choose `File -> New Torrent`.  Tell it to `Use Vuze Embedded Tracker` and click `Next`.  Add the `<yourimage.cdr>` file as the only file to the torrent, and click `Next`. It will tell you where it'll save the torrent.  Tell it to `Open the torrent for seeding when done` and to `Host the torrent on the build-in tracker`.  (I don't know if the decentralized tracking option is good or not, and left it on).  Click `Next`.  It'll build the torrent.  When it is done, you'll likely want to open it up in the Finder.

One last thing that I think is helpful.  Find your torrent within Vuze -- probably by clicking on `Inactive` on the left column.  Then, in the right pane, click on the representation of the file and tell it to `Force Start`.  This keeps it seeding your torrent.  [I've had problems where my peers weren't getting any data, and the seed wasn't offering any.  Don't know why.]

3, 4, 5 and 6 -- run the script.
------------

I'd suggest downloading this whole project here from github.  You may need to make the items in the `scripts` folder executable.

You'll need to run the script in Terminal.  You'll have to specify the partition to restore and the file to restore from.

Figure out which partition you want to restore to, either the device name (as in step 1), or the path name, if it is mounted (such as "/Volumes/Target Partition").

Now, specify the file you want to restore -- either a `.cdr` file or a `.cdr.torrent` file.  (You'll have to copy the `.torrent` file to the target computer if it is not already there).  Note that when it comes time to specify this option, you can drag and drop the file into the Terminal and it'll specify the file.

Note that the script must be run as root to write to file partitions.

Here are two example invocations:

    sudo /path/to/scripts/restore_partition_from_torrent.sh "/Volumes/Target Disk" /path/to/my_awesome_partition.cdr.torrent

or

    sudo /path/to/scripts/restore_partition_from_torrent.sh disk0s4 /path/to/my_awesome_partition.cdr


The script runs.  It does some sanity checks and you'll be asked if you are sure you want to proceed.

To get a feel for what the script looks like when run, see the file 'sample output.txt'.


7. Profit!
-------

Well, this will be most profitable, or most useful, when it can be used for imaging computers.  I'd love to make it operate with Deploy Studio or Casper so that a computer can be netbooted and imaged.

### Enhancements and difficulties:

Of course, this isn't quite done.

Sometimes transmissioncli verifies a disk before laying down a torrent's contents, thinking you have a partially downloaded file already.  It doesn't seem to do that all the time, though.  I'm wondering if I need to modify the code.

Perhaps some different tool would be better.  I'm open to suggestions.  It is desirable to know what the progress is like, to stop it when it is done, and the system needs to be able to write the data to a hard drive partition (and a lot of data at that!)  It is also nice if it is fairly small and easily added to an imaging workflow (especially without rebuilding the NetBoot image).

(I'll note here that I did try libtornado, used by Twitter Murder, but it never finished downloading a 15 GB image.  I also tried rtorrent, but it mmaps files and I could not persuade it to write to a block or character device representing a disk partition.)

I'm also sure there is a lot of tweaking that would be advantageous.

If you have ideas, please give me a shout -- clinton.blackmore+btimaging@gmail.com -- or fork the repository and make it better!


Third-Party Tools
-----------

I am including two compiled binaries of third-party tools with the scripts.

=== Pipe Viewer
[pv](http://www.ivarch.com/programs/pv.shtml) is a great utility for seeing how much data has gone through a pipe.  I'm using it so that when you restore a .cdr file using dd, you can see how far along the process is. `pv` is under an artistic license.

=== Transmission
Transmission is a BitTorrent client.  I'm including the command-line interface program `transmissioncli`, unchanged from Transmission 2.82, at present.  Transmission is under the GPL, with parts under an MIT license.

See the licenses folder for more information.



