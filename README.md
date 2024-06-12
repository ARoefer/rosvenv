# ROSVENV - A lightweight tool for isolating ROS1

Have you ever found yourself begrudgingly installing python packages globally when using ROS1? Have you ever been annoyed by constantly having to configure your `ROS_IP` and `ROS_MASTER_URI` environment variables for your different robots? If your answer was "yes", then this little bash script is for you! 

**ROSVENV** is a very small set of bash scripts that help you to create and use catkin workspaces with isolated Python environments. It can source and un-source (is that even a word?) your workspace, and can configure your connection to distant ROS masters easily. 

Sounds good? Then come right on in!

(Only tested with noetic and Python3 so far, so, beware...)

## Installation

Installation is as easy as chewing gum!
First, either you need to have installed python's `venv` package or conda:

- venv
    ```
    # For all ROS versions. Python 2 does not have venv
    sudo apt install python3-venv

    ```
- conda
    https://conda.io/projects/conda/en/latest/user-guide/install/index.html#regular-installation

Then, simply `cd` to the root of this repository and run the install script:

```bash
cd path/to/rosvenv
source install_rosvenv.bash
```

You can also do `./install_rosvenv.bash`, but then you'll have to re-source `.bashrc`.

What did the install script just do to your system you ask? Well, it simply copied the file `rosvenv.bash` to `~/.rosvenv.bash` and added `source ~/.rosvenv.bash` to your `~/.bashrc`. Re-running the script will only perform the copy again, but will not modify your `.bashrc` unless the function `createROSWS` is nowhere to be found.

# Uninstall
To uninstall rosvenv, you cat just delete `~/.rosvenv.bash` and remove the following lines from your `.bashrc`.
```
# ROSVENV
source ~/.rosvenv.bash
export ROSVENV_ROOT=<PATH>
```

## The ROSVENV-Commands

ROSVENV provides a whole six (6!) commands. Let's go over them...

### createROSWS

```
createROSWS path/to/new/ws
```

This is probably the first command you will try out. `createROSWS` takes a path for a directory to create and initializes a new catkin workspace within it. If ROS is not sourced it will source your installed version from `/opt/ros/*/setup.bash`. **NOTE**: If you, however you managed that, have multiple ROS versions installed, it will source all of them. In that case you should source ROS manually first.

If, when running the command you have an active conda environment, its name will be saved to a `condenv.txt` placed in the root of the workspace for later automatic activation.
Otherwise, it has created a `pyenv` directory containing the venv for your workspace. The structure of your workspace should look something like this:

```
ws
├── build
├── devel
├── logs
├── pyenv (optional)
├── condenv.txt (optional)
├── pypath (optional)
└── src
``` 

In the diagram above, you can see the `pypath` file which is marked as *optional*. This file is a copy of `~/.pypath`, if that file exists. Its purpose will be explained in the next section.

The creation process will invoke `catkin build` once to generate the necessary `setup.bash` file and will then activate your newly created workspace.

### activateROS

This command you'll probably use the most. It *activates* a workspace, sourcing its `setup.bash`, activating the respective virtual environment (conda or venv), and setting your `ROS_IP` and `ROS_MASTER_URI` to your local machine.

Its single argument is the path to the root of the workspace you want to activate. If you do not give any argument, it will default to `~ws`. If you have a primary workspace you work on most of the time, you can link it to that path.

The activation command can also modify your `PYTHONPATH` variable with custom paths stored in `pypath` at the root of the workspace. The paths are stored one per line:

```
path/a
path/b
path/c
...
```

### deactivateROS

This command simply deactivates the ROS workspace again. It restores the paths that were modified by the catkin setup files and deactivates the virtual environment as well.

While it does not take any arguments, one thing should be noted about it: It will unset **all** environment variables with `ROS` in the name.

### reloadROS

At times, especially after building a new package, catkin will require the workspace to be re-sourced. This command does just that!

### makeROSMaster

This command will come in handy once you are ready to work with your actual robot friend. It changes the `ROS_MASTER_URI` and optionally also `ROS_IP` variables to connect you to a remote master. 

Usually you will simply pass the name/IP of the remote ROS master to the command:

```bash
$ makeROSMaster 192.137.131.1
Changed ROS-Master!
ROS-IP: 127.0.0.1
ROS MASTER URI: http://192.137.131.1:11311

```

However, sometimes this pattern will not suffice. For those cases you can specify exceptions in the `~/.ros_ips` or `WS/ros_ips` files. The file from the workspace overrides whatever might be specified in the file in `~`.

Exceptions are formulated like this:

```
foo_IP=192.137.131.22
foo_URI=http://192.137.131.1:11311
bar_IP=66.137.131.22
bar_URI=http://66.137.131.1:11311
...
```
Please make sure that the files close with **exactly** one newline.
You can also specify only IP or URI for an exception, it does not have to be both. Given the config obove, you can use `makeROSMaster foo` to set the `ROS_IP`, and `ROS_MASTER_URI` environment variables to `192.137.131.22` and `http://192.137.131.1:11311` respectively.

Lastly, if you do not want to always have to type the host name, you can add a `DEFAULT=MY_CONFIG_NAME` line to either of the `ros_ips` files, which will cause the command to default to that host. In some cases, such as `rosvenv` being deployed on a robot, you will always want to use a non-standard URI/IP setup. For this case, you can add an `AUTO=MY_CONFIG_NAME` line to the config file. The designated host will be automatically configured whenever a workspace is activated.

### refreshROSEnvFile

For editors, namely VSCode, the catkin package structure represents a problem when running Python applications in debugger or running Jupyter notebooks, as the kernels do not find catkin packages. This can be remmedied by using a `.env` file which contains the necessary environment variables to locate the packages. The `refreshROSEnvFile` automatically recovers these variables and writes them to `WS/ros.env`. You can then set this file [to be used by VSCode](https://code.visualstudio.com/docs/python/environments#_environment-variable-definitions-file). Note, that there is a separate setting [for debug configs](https://code.visualstudio.com/docs/python/debugging#_envfile), in case you run into trouble with the global setting.

## Conclusion

That's it! I hope this makes working with ROS a bit easier for you. If you find a bug, feel free to post and issue.

## Actually, that's not it: Let's Dockerize

As time moves on and Ubuntu versions get discarded, so this happened to Ubuntu 20.04 -- the last version officially supporting trusty ROS1. As most of our robots still run ROS1 and most of our tools are ROS1, this is a catastrophic development and must be dealt with. Instead of trying to figure out how to install ROS1 on future versions of Ubuntu, ROSVENV opts for eternally cocooning itself in the save embrace of a docker container.
Everything you have learned about the workflow with ROSVENV so far remains the same, but you need to install docker on your system.

### Installing Docker

Follow the official instructions for installing docker (https://docs.docker.com/engine/install/ubuntu/) and add yourself to the `docker` group so you don't have to have sudo rights to use docker:

```bash
sudo usermod -aG docker $USER
```


