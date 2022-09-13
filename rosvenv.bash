# ROSVCONDA - Adrian Roefer, Jan Ole von Hartz (2022)

 CONDA_ENV_FILE_NAME="condenv.txt"

createROSWS() {
    if [ $# -ne 1 ] || [ $1 = "-h" ] || [ $1 = "--help" ]; then
        echo "Creates a new ROS catkin workspace under a given path."
        echo "Will copy ~/pypath to the new ws, if the file exists." 
        echo
        echo "Arguments: nameOfnewWS"
        echo
        return
    else
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
                CONDA_ENV_NAME=${CONDA_PREFIX##*/}
                echo "$CONDA_ENV_NAME" > $CONDA_ENV_FILE_NAME
                catkin build
                activateROS .
            else
                echo "Failed to create directory $1 for workspace."
            fi
        fi
    fi
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

        ws_dir=$1
    else
        ws_dir="${HOME}/ws"
    fi

    if [ -d ${ws_dir} ] || [ -L ${ws_dir} ]; then
        # Source distro's setup.bash if it hasn't happened yet
        _save_paths

        if [[ -z ${ROS_DISTRO} ]]; then
            source /opt/ros/*/setup.bash
        fi

        source "${ws_dir}/devel/setup.bash"
        CONDA_ENV_NAME=$(cat "$ws_dir/$CONDA_ENV_FILE_NAME")
        conda activate $CONDA_ENV_NAME

        if [ -f "${ws_dir}/pypath" ]; then
            export PYTHONPATH=$PYTHONPATH:$(tr '\n' ':' < "${ws_dir}/pypath")
        fi

        all_ips=`hostname -I`
        ip_array=(${all_ips})

        export ROS_IP="127.0.0.1"  #${ip_array[0]}
        export ROS_MASTER_URI=http://${ROS_IP}:11311

        export PS1="(ROS ${ROS_DISTRO}) ${PS1:-}"

        _ROS_WS_DIR=${ws_dir}

        printf "ROS activated!\nROS-IP: ${ROS_IP}\nROS MASTER URI: ${ROS_MASTER_URI}\n"
    else
        echo "Cannot activate ROS environment ${ws_dir} as it does not exist"
    fi
}

deactivateROS() {
    if [[ -z ${ROS_DISTRO} ]]; then
        echo "ROS is not active."
        return
    fi

    deactivate
    _restore_paths

    ros_vars=$(env | egrep -o '^[^=]+' | grep "ROS")
    for var in ${ros_vars[@]}; do
        unset ${var}
    done
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
