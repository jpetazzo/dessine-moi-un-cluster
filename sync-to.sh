#!/bin/sh
rsync --rsync-path="sudo rsync" -av bin/ $1:/usr/local/bin/

