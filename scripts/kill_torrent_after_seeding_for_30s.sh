#!/bin/sh

echo "\n\nKilling torrent after seeding for 30 more seconds\n\n"
sleep 30
killall transmissioncli
