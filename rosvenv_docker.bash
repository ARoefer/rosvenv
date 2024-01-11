# ========================================
#          ROSVENV DOCKER TOOLS
# ========================================

ROSVENV_DEFAULT_DOCKER_IMAGE="rosvenv:latest"

rosvenv_has_docker() {
    if $(command -v docker > /dev/null); then 
        return 0;
    fi
    return -1
}

rosvenv_docker_build_container() {
    if [ -z "$ROSVENV_ROOT" ]; then
        echo "It seems ROSVENV is not installed, or its root is not exported"
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

    docker_result=$(docker buildx build -t $tag . $args)

    if $docker_result; then
        echo "--- Successfully built your container ---"
    else
        echo "--- FAILURE: Please check output above ---"
    fi
    
    cd $_PWD
    return $docker_result
}

rosvenv_docker_image_exists() {
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

rosvenv_ws_docker_is_running() {
    if [ $# -lt 1 ]; then
        echo "Need name of workspace to check."
        return -1
    fi

    filtered_lines=$(docker ps | grep $1)
    for e in $filtered_lines; do
        if [ $e == $1 ]; then
            return 0
        fi
    done
    return -1
}

rosvenv_docker_start_ws_container() {
    if [ $# -lt 2 ]; then
        echo "Need name of image and workspace to start a container for."
        return -1
    fi

    docker run --name $2 \
           --env DISPLAY=$DISPLAY \
           --gpus all \
           --env NVIDIA_VISIBLE_DEVICES=all \
           --env NVIDIA_DRIVER_CAPABILITIES=all \
           --env QT_X11_NO_MITSHM=1 \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           -d -v $HOME:$HOME --user $USER $1 \
           bash -c "while true; do sleep 0.5s; done"
}

rosvenv_docker_login_wrapper() {
    if [ $# -lt 2 ]; then
        echo "Need name of image, workspace to log into and optionally command to execute."
        return -1
    fi

    image_name=$1
    container_name=$2

    if ! $(rosvenv_ws_docker_is_running $container_name); then
        echo "Starting docker container \"$container_name\" with image \"$image_name\"..."
        rosvenv_docker_start_ws_container $image_name $container_name
    fi

    shift 2
    bash_instruction="printf \"source ~/.bashrc\nunset ROS_DISTRO\nexport ROSVENV_IN_DOCKER=1\n$*\n\" > /tmp/COMMAND; bash --init-file /tmp/COMMAND"

    docker exec -w $PWD -it $container_name bash -c "$bash_instruction"
}

rosvenv_docker_autobuild() {
    base_image_exists=$(rosvenv_docker_image_exists $ROSVENV_DEFAULT_DOCKER_IMAGE)

    if [[ $base_image_exists -ne 0 ]]; then
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