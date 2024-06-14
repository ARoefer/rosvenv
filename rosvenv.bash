# ROSENV - Adrian Roefer, Jan Ole von Hartz (2022)

CONDA_ENV_FILE_NAME="condenv.txt"

_rosvenv_precheck() {
    if [ -d "/opt/ros/noetic" ]; then
        return 0
    fi
    return -1
}

_rosvenv_print_help() {
    echo "Creates a new ROS catkin workspace under a given path."
    echo "Will copy ~/pypath to the new ws, if the file exists." 
    echo
    echo "Arguments: nameOfnewWS [Python version=python3] [--docker [image name | Dockerfile]]"
    echo
}

createROSWS() {
    original_args=$@
    
    ws_dir=""
    pythonCommand="python3"

    while [ : ]; do
        if [ $# -lt 1 ]; then
            break
        fi

        if [[ "$1" =~ (--help|-h) ]]; then
            _rosvenv_print_help
            return
        elif [[ "$1" =~ (--python) ]]; then
            if [ $#  -lt 2 ]; then
                _rosvenv_print_help
                echo "Argument --python requires a parameter"
                return -1
            fi

            pythonCommand=$2
            shift 2
        elif [[ "$1" =~ (--docker) ]]; then
            if [ $#  -lt 2 ]; then
                docker_image="$ROSVENV_DEFAULT_DOCKER_IMAGE"
                shift 1
            else
                docker_image="$2"
                shift 2
            fi
        elif [ -z "$ws_dir" ]; then
            ws_dir=`realpath $1`
            shift 1
        else
            _rosvenv_print_help

            echo "Unknown argument \"$1\""

            return -1
        fi
    done

    if ! _rosvenv_precheck && [ -z "$docker_image" ]; then
        echo "You seem to be missing ROS. Please install it, or " \
             "use the --docker option to use docker to run your environment"
        return -1
    fi

    if ! [ -z "$docker_image" ] && [ -z $ROSVENV_IN_DOCKER ]; then
        if ! rosvenv_has_docker; then
            echo "You are trying to create a docker workspace, but docker does not seem to be installed."
            return 1
        fi
    else
        if ! [ -x "$(command -v catkin)" ]; then
            echo $'You seem to be missing catkin tools. Install by running \n\n  sudo apt install python3-catkin-tools\n'
            return
        fi

        if ! [ -n "$(apt list --installed 2> /dev/null | grep $pythonCommand-venv)" ]; then
            echo "venv for ${pythonCommand} does not seem to be installed."
            return
        fi
    fi

    if [ -d "$ws_dir/src" ]; then
        echo "Given directory $ws_dir seems to already have been initialized."
    else
        if [ -z "$docker_image" ] || ! [ -z "$ROSVENV_IN_DOCKER" ]; then
            _save_paths

            if [[ -z ${ROS_DISTRO} ]]; then
                echo "ROS is not sourced. Sourcing it..."
                source /opt/ros/*/setup.bash
                echo "Sourced ${ROS_DISTRO}"
            fi
            
            mkdir -p "$ws_dir/src"
            
            if [ -d "$ws_dir/src" ]; then
                if [ -f "${HOME}/.pypath" ]; then
                    cp "${HOME}/pypath" $ws_dir/
                fi

                cd $ws_dir/src
                catkin_init_workspace
                cd ..
                if [[ -n "${CONDA_PREFIX}" ]]; then
                    echo "Creating conda env"
                    CONDA_ENV_NAME=$CONDA_DEFAULT_ENV
                    echo "$CONDA_ENV_NAME" > $CONDA_ENV_FILE_NAME
                    echo "Found activate conda env ${CONDA_ENV_NAME}. Saved it to workspace."
                else
                    echo "No activate conda env found. Creating venv."
                    eval $pythonCommand -m venv --system-site-packages pyenv
                    source pyenv/bin/activate
                fi

                catkin build
                deactivatePyEnv
                activateROS .
            else
                echo "Failed to create directory $ws_dir for workspace."
            fi
        else
            # Sets return register to 255 if image does not exist
            rosvenv_docker_image_exists $ROSVENV_DEFAULT_DOCKER_IMAGE

            if [[ $? -ne 0 ]]; then
                echo "ROSVENV base image does not seem to exist. Building it..."
                rosvenv_docker_build_container
            else
                echo "ROSVENV image exists"
            fi

            mkdir -p "$ws_dir"

            if [ -f "$docker_image" ]; then
                cp "$docker_image" "$ws_dir/Dockerfile"
                docker_image="$(_rosvenv_get_ws_image_name $ws_dir)"
                rosvenv_docker_autobuild "$docker_image" "$ws_dir"
            else
                echo "$docker_image" > "$ws_dir/docker_override"
            fi

            container_name="$(_rosvenv_ws_path_to_name $ws_dir)"

            rosvenv_docker_login_wrapper $docker_image $container_name $ws_dir "createROSWS" $original_args
        fi
    fi
}

_deactivatePyEnv() {
    if [[ -n "${CONDA_PREFIX}" ]]; then
        conda deactivate
    else
        deactivate
    fi
}

isROSWS() {
    # if ([ -f "$1/src/CMakeLists.txt" ] || [ -h "$1/src/CMakeLists.txt" ]) && [ -d "$1/pyenv" ]; then
    if [ -f "$1/condenv.txt" ] || [ -d "$1/pyenv" ]; then
        return 0
    fi

    return -1
}

_rosvenv_get_ws_image_name() {
    if [ -f "$1/Dockerfile" ]; then
        echo "${1##*/}:latest"
        return
    fi

    if [ -f "$1/docker_override" ]; then
        cat $1/docker_override
        return
    fi

    echo $ROSVENV_DEFAULT_DOCKER_IMAGE
}

_rosvenv_ws_has_docker() {
    if [ -f "$1/Dockerfile" ] || [ -f "$1/docker_override" ]; then
        return 0
    fi
    return -1
}

_rosvenv_ws_path_to_name() {
    echo "${1##*/}"
}

_rosvenv_find_ws_dir() {
    res_path=`realpath $1`
    pathIter="$res_path"
    while [ "$pathIter" != "/" ] && ! isROSWS $pathIter; do
        pathIter=`realpath "$pathIter/.."`
    done

    if ! $(isROSWS $pathIter); then
        echo "Could not find a ROS workspace while traversing upwards from $res_path"
        return -1
    fi
    echo $pathIter
    return 0
}

activateROS() {
    # Set default workspace if none was given
    if [ $# -eq 1 ]; then
        if [ $1 = "-h" ] || [ $1 = "--help" ]; then
            echo "Sources a ROS environment previously created by createROSWS."
            echo "This includes sourcing the local conda env and, optionally, extending PYTHONPATH"
            echo 
            echo "Arguments: [path to ws root=~/ws]"
            echo
            return
        fi

        ws_dir=`realpath $1`
    else
        ws_dir=`realpath $PWD`
    fi

    pathIter="$ws_dir"
    while [ "$pathIter" != "/" ] && ! isROSWS $pathIter; do
        pathIter=`realpath "$pathIter/.."`
    done

    if isROSWS $pathIter; then
        ws_dir=$pathIter
    else
        echo "Could not find a ROS workspace while traversing upwards from $ws_dir"
        return -1
    fi

    if ! _rosvenv_precheck || ([ -z $ROSVENV_IN_DOCKER ] && $(_rosvenv_ws_has_docker $ws_dir)); then
        docker_image="$(_rosvenv_get_ws_image_name $ws_dir)"
        echo "Signing into docker ($docker_image) for workspace $ws_dir"

        if ! rosvenv_docker_autobuild $docker_image $ws_dir; then
            return -1
        fi

        container_name="$(_rosvenv_ws_path_to_name $ws_dir)"
        rosvenv_docker_login_wrapper $docker_image $container_name $ws_dir "activateROS" $*
    elif [ -d ${ws_dir} ] || [ -L ${ws_dir} ]; then
        # Source distro's setup.bash if it hasn't happened yet
        _save_paths

        if [[ -z ${ROS_DISTRO} ]]; then
            source /opt/ros/*/setup.bash
        fi

        source "${ws_dir}/devel/setup.bash"
        if test -f "$ws_dir/$CONDA_ENV_FILE_NAME"; then
            echo "Found conda env. Sourcing"
            CONDA_ENV_NAME=$(cat "$ws_dir/$CONDA_ENV_FILE_NAME")
            conda activate $CONDA_ENV_NAME
        else
            echo "No conda env found. Sourcing venv"
            source "${ws_dir}/pyenv/bin/activate"
            _rename_function deactivate _deactivate
        fi


        if [ -f "${ws_dir}/pypath" ]; then
            export PYTHONPATH=$PYTHONPATH:$(tr '\n' ':' < "${ws_dir}/pypath")
        fi

        all_ips=`hostname -I`
        ip_array=(${all_ips})

        export ROS_IP="127.0.0.1"  #${ip_array[0]}
        export ROS_MASTER_URI=http://${ROS_IP}:11311

        export PS1="(ROS ${ROS_DISTRO}) ${PS1:-}"

        _ROS_WS_DIR=${ws_dir}

        local -A ROS_IP_DICT=$(_loadIPDict)

        if [ ${ROS_IP_DICT[AUTO]+_} ]; then
            printf "ROS activated!\nAuto activating ROS master '${ROS_IP_DICT[AUTO]}'\n"
            makeROSMaster ${ROS_IP_DICT[AUTO]}
        else
            printf "ROS activated!\nROS-IP: ${ROS_IP}\nROS MASTER URI: ${ROS_MASTER_URI}\n"
        fi

    else
        echo "Cannot activate ROS environment ${ws_dir} as it does not exist"
    fi
}

rosvenvStopContainer() {
    if [[ $ROSVENV_IN_DOCKER -eq 1 ]]; then
        echo "You seem to currently be inside a container. Containers can only be stopped from the host system."
        return -1
    fi

    if [ $# -eq 1 ]; then
        ws_dir=`realpath $1`
    else
        ws_dir=`realpath $PWD`
    fi

    ws_dir="$(_rosvenv_find_ws_dir $ws_dir)"

    if [ $? -ne 0 ]; then
        echo $ws_dir
        return -1
    fi

    if ! $(_rosvenv_ws_has_docker $ws_dir); then
        echo "Workspace $ws_dir is not set to run in docker"
        return -1
    fi

    container_name="$(_rosvenv_ws_path_to_name $ws_dir)"
    if $(rosvenv_ws_docker_exists $container_name); then
        docker rm -f $container_name > /dev/null
        echo "Stopped container $container_name"
    else
        echo "Container $container_name does not seem to be active"
    fi
}

rosvenvRestartContainer() {
    if [[ $ROSVENV_IN_DOCKER -eq 1 ]]; then
        echo "You seem to currently be inside a container. Containers can only be restarted from the host system."
        return -1
    fi

    if [ $# -eq 1 ]; then
        ws_dir=`realpath $1`
    else
        ws_dir=`realpath $PWD`
    fi

    ws_dir="$(_rosvenv_find_ws_dir $ws_dir)"

    if [ $? -ne 0 ]; then
        echo $ws_dir
        return -1
    fi

    if ! $(_rosvenv_ws_has_docker $ws_dir); then
        echo "Workspace $ws_dir is not set to run in docker"
        return -1
    fi

    container_name="$(_rosvenv_ws_path_to_name $ws_dir)"
    if $(rosvenv_ws_docker_exists $container_name); then
        docker rm -f $container_name > /dev/null
    fi

    activateROS $ws_dir
}

rosvenvRebuildContainer() {
    if [[ $ROSVENV_IN_DOCKER -eq 1 ]]; then
        echo "You seem to currently be inside a container. Containers can only be rebuilt from the host system."
        return -1
    fi

    if [ $# -eq 1 ]; then
        ws_dir=`realpath $1`
    else
        ws_dir=`realpath $PWD`
    fi

    ws_dir="$(_rosvenv_find_ws_dir $ws_dir)"

    if [ $? -ne 0 ]; then
        echo $ws_dir
        return -1
    fi

    if ! $(_rosvenv_ws_has_docker $ws_dir); then
        echo "Workspace $ws_dir is not set to run in docker"
        return -1
    fi

    image_name="$(_rosvenv_get_ws_image_name $ws_dir)"

    if [[ "$image_name" == "$ROSVENV_DEFAULT_DOCKER_IMAGE" ]]; then
        rosvenv_docker_build_container
    elif [ -f "${ws_dir}/Dockerfile" ]; then
        rosvenv_docker_build_container $image_name $ws_dir
    else
        echo "Cannot rebuild image of $ws_dir as workspace does not depend on rosvenv:latest and does not have a Dockerfile"
        return -1 
    fi

    rosvenvRestartContainer $ws_dir
}

_copy_function() {
  test -n "$(declare -f "$1")" || return 
  eval "${_/$1/$2}"
}

_rename_function() {
  _copy_function "$@" || return
  unset -f "$1"
}


deactivateROS() {
    if [[ -z ${ROS_DISTRO} ]]; then
        echo "ROS is not active."
        return
    fi

    if [[ $ROSVENV_IN_DOCKER -eq 1 ]]; then
        exit 0
    fi

    _rename_function _deactivate deactivate
    _deactivatePyEnv
    _restore_paths

    ros_vars=$(env | egrep -o '^[^=]+' | grep "ROS")
    for var in ${ros_vars[@]}; do
        unset ${var}
    done
}


reloadROS() {
    if [[ -z ${_ROS_WS_DIR} ]]; then
        echo "No ROS workspace active."
        return
    fi

    echo "Reloading workspace ${_ROS_WS_DIR}"

    if [[ $ROSVENV_IN_DOCKER -eq 1 ]]; then
        _in_docker=1
        unset ROSVENV_IN_DOCKER
    else
        _in_docker=0
    fi

    temp_ws_path=${_ROS_WS_DIR}
    deactivateROS

    # Avoid exiting docker
    if [[ $_in_docker -eq 1 ]]; then
        export ROSVENV_IN_DOCKER=1
    fi

    activateROS ${temp_ws_path}
}

refreshROSEnvFile() {
    if [[ -z ${_ROS_WS_DIR} ]]; then
        echo "No ROS workspace active."
        return
    fi

    echo "Regenerating the \"ros.env\" file for ${_ROS_WS_DIR}."

    env | grep -E "(PATH|ROS)" | grep -v PS1 > "${_ROS_WS_DIR}/ros.env"

    echo "Done."
}

_loadIPDict() {
    local -A ROS_IP_DICT
    if [ -f "${HOME}/.ros_ips" ]; then
        while IFS= read -r line; do
            ROS_IP_DICT[${line%%=*}]=${line#*=}
        done < "${HOME}/.ros_ips"            
    fi

    if [[ ! -z "${_ROS_WS_DIR}" ]] && [ -f "${_ROS_WS_DIR}/ros_ips" ]; then
        while IFS= read -r line; do
            ROS_IP_DICT[${line%%=*}]=${line#*=}
        done < "${_ROS_WS_DIR}/ros_ips"
    fi
    echo '('
    for key in  "${!ROS_IP_DICT[@]}" ; do
        echo "[$key]=${ROS_IP_DICT[$key]}"
    done
    echo ')'
}


makeROSMaster() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "Sets the ROS master URI and ROS IP of this machine."
        echo "Need the IP or name of the new ROS-master."
        echo
        echo "Will try to find aliases for the given master from ~/.ros_ips and WORKSPACE/ros_ips"
        echo
    else
        if [[ -z ${ROS_DISTRO} ]]; then
            echo "ROS needs to be sourced for this command"
            return
        fi

        local -A ROS_IP_DICT=$(_loadIPDict)

        if [ $# = 0 ]; then
            if [ ${ROS_IP_DICT[DEFAULT]+_} ]; then
                ros_master="${ROS_IP_DICT[DEFAULT]}"
                echo "Defaulting to master '${ros_master}'"
            else
                echo "When no IP is specified, either ~/.ros_ips or WORKSPACE/ros_ips need to define a key 'DEFAULT' storing a default master"
                return
            fi
        else
            ros_master=$1
        fi

        # Exception for the network specific to our PR2 setup
        if [ ${ROS_IP_DICT["${ros_master}_IP"]+_} ]; then
            echo "Found custom IP for master '${ros_master}'"
            export ROS_IP=${ROS_IP_DICT["${ros_master}_IP"]}
        fi
        
        if [ ${ROS_IP_DICT["${ros_master}_URI"]+_} ]; then
            echo "Found custom URI for master '${ros_master}'"
            export ROS_MASTER_URI=${ROS_IP_DICT["${ros_master}_URI"]}
        else
            export ROS_MASTER_URI="http://${ros_master}:11311"
        fi

        printf "Changed ROS-Master!\nROS-IP: ${ROS_IP}\nROS MASTER URI: ${ROS_MASTER_URI}\n"
    fi
}

_save_paths() {
    if [[ -z "${_OLD_PYTHONPATH}" ]]; then
        _OLD_PYTHONPATH=${PYTHONPATH}
    fi
    if [[ -z "${_OLD_PKG_CONFIG_PATH}" ]]; then
        _OLD_PKG_CONFIG_PATH=${PKG_CONFIG_PATH}
    fi
    if [[ -z "${_OLD_CMAKE_PREFIX_PATH}" ]]; then
        _OLD_CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}
    fi
    if [[ -z "${_OLD_LD_LIBRARY_PATH}" ]]; then
        _OLD_LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
    fi
    if [[ -z "${_OLD_PATH}" ]]; then
        _OLD_PATH=${PATH}
    fi
}

_restore_paths() {
    if [[ -z "${_OLD_PKG_CONFIG_PATH}" ]]; then
        unset PKG_CONFIG_PATH
    else    
        export PKG_CONFIG_PATH=${_OLD_PKG_CONFIG_PATH}
    fi
    if [[ -z "${_OLD_CMAKE_PREFIX_PATH}" ]]; then
        unset CMAKE_PREFIX_PATH
    else    
        export CMAKE_PREFIX_PATH=${_OLD_CMAKE_PREFIX_PATH}
    fi
    if [[ -z "${_OLD_LD_LIBRARY_PATH}" ]]; then
        unset LD_LIBRARY_PATH
    else    
        export LD_LIBRARY_PATH=${_OLD_LD_LIBRARY_PATH}
    fi
    if [[ -z "${_OLD_PATH}" ]]; then
        unset PATH
    else    
        export PATH=${_OLD_PATH}
    fi
    if [[ -z "${_OLD_PYTHONPATH}" ]]; then
        unset PYTHONPATH
    else    
        export PYTHONPATH=${_OLD_PYTHONPATH}
    fi
    unset _OLD_PKG_CONFIG_PATH
    unset _OLD_CMAKE_PREFIX_PATH
    unset _OLD_LD_LIBRARY_PATH
    unset _OLD_PATH
    unset _OLD_PYTHONPATH
}
