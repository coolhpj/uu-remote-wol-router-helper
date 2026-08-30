#!/bin/sh

cd /usr/lib/uu-wol-helper || exit 1
exec ./uuplugin ./uu.conf
