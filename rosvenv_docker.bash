# ========================================
#          ROSVENV DOCKER TOOLS
# ========================================

ROSVENV_DEFAULT_DOCKER_IMAGE="rosvenv:latest"

rosvenv_has_docker() {
    # Checks if docker is installed on the system.

    if $(command -v docker > /dev/null); then 
        return 0;
    fi
    return -1
}

rosvenv_has_nvctk() {
    # Checks if docker is installed on the system.

    if $(command -v nvidia-ctk > /dev/null); then 
        return 0;
    fi
    return -1
}

rosvenv_docker_build_container() {
    # (Re-)builds a ROSVENV docker container. If no arguments are given,
    # it will build the ROSVENV base container.
    # args: [directory containing Dockerfile, tag of container, [additional args for build]]

    if [ -z "$ROSVENV_ROOT" ]; then
        echo "It seems ROSVENV is not installed, or its root is not exported. Maybe you need to re-source your bashrc."
        return -1
    fi

    _PWD=$PWD
    
    if [ $# -gt 0 ] && [ $# -lt 2 ]; then
        echo "Need at least path and image tag, if overrides are given"
        return -1
    fi

    if [ $# -gt 0 ]; then
        cd $1
        tag=$2
        if [ $# -gt 2 ]; then
            shift 2
            args="*$"
        fi
    else
        cd $ROSVENV_ROOT
        tag="rosvenv:latest"
        args="--build-arg USER_NAME=$USER --build-arg USER_ID=$UID --build-arg USER_GID=$GROUPS"
    fi

    echo "--- Building your personal ROSVENV docker container tagged \"${tag}\" ---"

    docker buildx build -t $tag . $args
    docker_result=$?

    if [ $docker_result -eq 0 ]; then
        echo "--- Successfully built your container ---"
    else
        echo "--- FAILURE: Please check output above ---"
    fi

    cd $_PWD
    return $docker_result
}

rosvenv_docker_image_exists() {
    # Checks if a docker image of a given name exists
    # args: name of the image

    if [ $# -lt 1 ]; then
        echo "Need image name to check for"
        return -1
    fi

    _IFS=$IFS
    IFS=":"
    read -r -a NAME_ARR <<< $1
    image_name="${NAME_ARR[0]}"
    IFS=$_IFS

    if [ -z "$(docker images $1 | grep $image_name)" ]; then
        return -1
    fi

    return 0
}

rosvenv_ws_docker_exists() {
    # Checks if a workspace container is active in some form.
    # args: name of workspace

    if [ $# -lt 1 ]; then
        echo "Need name of workspace to check."
        return -1
    fi

    if [ -n "$(docker ps --filter "name=$1" -qa)" ]; then
        return 0
    fi
    return -1
}

rosvenv_ws_docker_is_running() {
    # Checks if a workspace container is already running.
    # args: name of workspace

    if [ $# -lt 1 ]; then
        echo "Need name of workspace to check."
        return -1
    fi

    if [[ "$(docker ps --filter "name=$1" --format "{{.State}}")" == "running" ]]; then
        return 0
    fi
    return -1
}

rosvenv_docker_start_ws_container() {
    # Starts a docker container for a workspace.
    # args: name of image, name of container, [additional arguments to pass to docker run]

    if [ $# -lt 2 ]; then
        echo "Need name of image, workspace name, and workspace dir to start a container for."
        return -1
    fi

    gpu_options=""
    if ! rosvenv_has_nvctk; then
        echo "Found no installation of nvidia-container-toolkit."
    else
        echo "Found installation of nvidia-container-toolkit. Exposing your GPUs to the container..."
        gpu_options="--gpus all --env NVIDIA_VISIBLE_DEVICES=all --env NVIDIA_DRIVER_CAPABILITIES=all"
    fi

    image_name=$1
    container_name=$2
    shift 2

    docker run --name $container_name \
           --network=host \
           --hostname $container_name \
           --env DISPLAY=$DISPLAY \
           $gpu_options \
           $@ \
           --env QT_X11_NO_MITSHM=1 \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           -d -v $HOME:$HOME --user $USER $image_name \
           bash -c "while true; do sleep 0.5s; done"
}

rosvenv_docker_login_wrapper() {
    # Wrapper for starting and logging into a container with additional re-execution of command in container
    # args: name of the image, name of container, workspace directory, [command and args to run in container]

    if [ $# -lt 4 ]; then
        echo "Need name of image, workspace to log into and optionally command to execute."
        return -1
    fi

    image_name=$1
    container_name=$2
    ws_dir=$3
    container_args=""

    if $(rosvenv_ws_docker_exists $container_name) && ! $(rosvenv_ws_docker_is_running $container_name); then
        echo "Container seems to be present but inactive. Restarting it..."
        docker rm -f $container_name > /dev/null
    fi

    if [ -f "${ws_dir}/docker_args" ]; then
        container_args="$(tr '\n' ' ' < ${ws_dir}/docker_args)"
    fi

    if ! $(rosvenv_ws_docker_is_running $container_name); then
        echo "Starting docker container \"$container_name\" with image \"$image_name\"..."
        rosvenv_docker_start_ws_container $image_name $container_name $container_args
    fi


    shift 3
    bash_instruction="printf \"source ~/.bashrc\nunset ROS_DISTRO\nexport ROSVENV_IN_DOCKER=1\n$*\n\" > /tmp/COMMAND; bash --init-file /tmp/COMMAND"

    docker exec -w $PWD -it $container_name bash -c "$bash_instruction"
}

rosvenv_docker_autobuild() {
    # Builds a custom docker container and the ROSVENV base container if it does not already exist
    # args: name of image, path of dir containing Dockerfile

    if ! $(rosvenv_docker_image_exists $ROSVENV_DEFAULT_DOCKER_IMAGE); then
        rosvenv_docker_build_container
    fi

    if [[ "$1" != "$ROSVENV_DEFAULT_DOCKER_IMAGE" ]] && ! $(rosvenv_docker_image_exists $1); then
        if ! [ -f "$2/Dockerfile" ]; then
            echo "Cannot build docker image $1 as $2 does not contain a docker file"
            return -1
        fi

        rosvenv_docker_build_container $2 $1
    fi
}
