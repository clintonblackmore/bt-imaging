#!/bin/sh

echo $@

echo $@ >> /Users/clinton/all_params.txt

say $@

#echo "\n\nKilling torrent after seeding for 30 more seconds\n\n"
#sleep 30
#killall transmissioncli
