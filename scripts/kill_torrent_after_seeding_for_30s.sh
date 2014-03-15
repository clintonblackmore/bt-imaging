#!/bin/sh

say hi
echo `tput bold`"Killing torrent after seeding for 30 more seconds"`tput sgr0`
sleep 30
killall transmissioncli
#echo `tput bold`"Killing torrent."`tput sgr0`
