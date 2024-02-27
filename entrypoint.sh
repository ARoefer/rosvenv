#!/bin/bash
set -e

# Move to home and source env
unset ROS_DISTRO # Needed because ROSVENV uses this var to tell if ROS is sourced

_PWD=$PWD
cd ~
source .bashrc
cd $_PWD
exec "$@"

