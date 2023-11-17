# ROSENV - Adrian Roefer, Jan Ole von Hartz (2022)

CONDA_ENV_FILE_NAME="condenv.txt"

createROSWS() {
    if [ $# -lt 1 ] || [ $1 = "-h" ] || [ $1 = "--help" ]; then
        echo "Creates a new ROS catkin workspace under a given path."
        echo "Will copy ~/pypath to the new ws, if the file exists." 
        echo
        echo "Arguments: nameOfnewWS [Python version=3]"
        echo
        return
    else
        if [ $# -ge 2 ]; then
            pythonCommand="python$2"
        else
            pythonCommand="python3"
        fi

        if ! [ -x "$(command -v catkin)" ]; then
            echo $'You seem to be missing catkin tools. Install by running \n\n  sudo apt install python3-catkin-tools\n'
            return
        fi

        if ! [ -n "$(apt list --installed 2> /dev/null | grep $pythonCommand-venv)" ]; then
            echo "venv for ${pythonCommand} does not seem to be installed."
            return
        fi

        if [ -d $1 ]; then
            echo "Given directory $1 already exists"
        else
            _save_paths

            if [[ -z ${ROS_DISTRO} ]]; then
                echo "ROS is not sourced. Sourcing it..."
                source /opt/ros/*/setup.bash
                echo "Sourced ${ROS_DISTRO}"
            fi
            
            mkdir -p "$1/src"
            
            if [ -d "$1/src" ]; then
                if [ -f "${HOME}/.pypath" ]; then
                    cp "${HOME}/pypath" $1/
                fi

                cd $1/src
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
                echo "Failed to create directory $1 for workspace."
            fi
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
    if [ -f "$1/src/CMakeLists.txt" ] && [ -d "$1/pyenv" ]; then
        return 0
    fi
    return -1
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

    if [ -d ${ws_dir} ] || [ -L ${ws_dir} ]; then
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

    temp_ws_path=${_ROS_WS_DIR}
    deactivateROS
    activateROS ${temp_ws_path}
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
