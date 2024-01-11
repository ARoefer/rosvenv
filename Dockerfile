FROM osrf/ros:noetic-desktop-full

# Copying your user credentials
ARG USER_NAME
ARG USER_ID
ARG USER_GID

# Adding typical tools we need or like to have
RUN apt-get update && apt-get install -q -y --no-install-recommends \
    vim \
    python3-venv \
    python3-catkin-tools \
    ros-noetic-catkin \
    git

# Needs to be removed because of the way ROSVENV works
ENV ROS_DISTRO=""

COPY ./entrypoint.sh /ros_entrypoint.sh

RUN useradd -Ms /bin/bash $USER_NAME && \
    usermod -aG sudo $USER_NAME && \
    usermod -u $USER_ID $USER_NAME && \
    groupmod -g $USER_GID $USER_NAME

# Start in your home dir
WORKDIR /home/$USER_NAME
