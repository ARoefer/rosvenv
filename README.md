# ROSVENV - A lightweight tool for isolating (and dockerizing) ROS1

Have you ever found yourself begrudgingly installing python packages globally when using ROS1? Have you ever been annoyed by constantly having to configure your `ROS_IP` and `ROS_MASTER_URI` environment variables for your different robots? If your answer was "yes", then this little bash script is for you! 

**ROSVENV** is a very small set of bash scripts that help you to create and use catkin workspaces with isolated Python environments. It can source and un-source (is that even a word?) your workspace, and can configure your connection to distant ROS masters easily.
*Even more*: With the discontinuation of support for ROS1 for Ubuntu versions beyond 20.04, ROSVENV can help you with dockerizing your ROS1 workflow so you can continue it on higher Ubuntu versions (currently tested with 22.04).

Sounds good? Then come right on in!

(Only tested with noetic and Python3 so far, so, beware...)

## Installation

Installation is as easy as chewing gum! That being said, if you are using Ubuntu 22.04+, you should probably [install docker](#install_docker) first.
In case you do not want to run ROSVENV in docker you need to have installed either python's `venv` package or conda:

- venv
    ```
    # For all ROS versions. Python 2 does not have venv
    sudo apt install python3-venv

    ```
- conda
    https://conda.io/projects/conda/en/latest/user-guide/install/index.html#regular-installation

Simply source the install script:

```bash
source path/to/rosvenv/install_rosvenv.bash
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

In case you used docker, use

```bash
docker rm -f "$(docker ps --filter "name=_ws" -q)"
```
to kill all your running workspace containers (this assumes that all your workspaces contain `_ws` in their name). 
Use `docker image rm rosvenv:latest` to remove the ROSVENV base image. Unfortunately there is currently no way to remove all dependent images. Use `docker image list -a` to list all images and remove the undesired ones with `docker image rm image_name`.

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

That's it! We hope this makes working with ROS a bit easier for you. If you find a bug, feel free to post and issue.

## The Post-20.04 World: Let's Dockerize

As the world moves on and Ubuntu versions get discarded, so this happened to Ubuntu 20.04 - the last version officially supporting trusty ROS1. As most of our robots still run ROS1 and most of our tools are ROS1, this is a catastrophic development and must be dealt with. Instead of trying to figure out how to install ROS1 on future versions of Ubuntu, ROSVENV opts for eternally cocooning itself in the save embrace of a docker container.
Everything you have learned about the workflow with ROSVENV so far remains the same, but you need to install docker on your system.

### <a name="install_docker"></a> Installing Docker

Follow the official instructions for installing docker (https://docs.docker.com/engine/install/ubuntu/) and add yourself to the `docker` group so you don't have to have sudo rights to use docker:

```bash
sudo usermod -aG docker $USER
```

After changing your membership, you'll have to log out and back in again for the change to take effect. (Sometimes a system reboot is required as well). Use `groups` to check that your membership in the `docker` group has been recognized. To check that docker has been installed successfully, run `docker run hello-world`. 

If you have an Nvidia GPU, you'll also want to install the `nvidia-container-toolkit` as described here: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html. You do not need to run the configuration step after installing the toolkit using `apt`. Simply restart the docker daemon: `sudo systemctl restart docker`.

### Dockerizing your Workspaces

The overall workflow with ROSVENV remains the same. `createROSWS` creates a workspace, `activateROS` activates a workspace. Docker acts as a hidden layer in both cases.

To create a dockerized workspace pass the `--docker` option to `createROSWS`. By default `createROSWS` will use the `rosvenv:latest` image to do so. This is a basic image built on top of the `osrf/ros:noetic-desktop-full` image. The most important thing this small expansion does, is mirror your user details into the container so that you can work on your host system without creating weird file ownership issues. It also adds `venv` and other small tools like `git` that the base image is missing. 

You can also use custom images, but you should always base them on the `rosvenv:latest` image. To create a workspace with a custom image, pass the name of the image or the path to the `Dockerfile` to `--docker` like so:

```bash
# Custom pre-built image
createROSWS my_ws --docker my_image:tag

# Image based on Dockerfile
createROSWS my_ws --docker path/to/some/Dockerfile
```

In case of the `Dockerfile` the file will be copied to the root of the workspace, in the other case a file `docker_override` will be created at the root. These files serve as indicators for ROSVENV that this is a containerized workspace. When you activate a workspace with `activateROS`, ROSVENV will automatically launch the matching container image, or sign into the container if it is already running.

### Working inside a container

Working inside a container is no different from working on your regular system. The commands mentioned above do the same thing as they do outside, except for `deactivateROS` making you leave the container. Alternatively you can also use `Ctrl+D` to leave the container. You can tell that you are inside the container by looking at your bash prompt, as the container identifies as a host with the name of your workspace:

```bash
# Outside of container
me@my_machine:~ $ activateROS my_ws

>> Signing into docker (rosvenv:latest) for workspace /home/me/my_ws
>> Starting docker container "my_ws" with image "rosvenv:latest"...
>> Found installation of nvidia-container-toolkit. Exposing your GPUs to the container...
>> 1ad1aecc6325bafd4dbe3dbfe71d8ab8fb998ebdd4b0d13c170f4dbc4d44873b
>> No conda env found. Sourcing venv
>> ROS activated!
(ROS noetic) (pyenv) me@my_ws:~ $ # Now we're inside the container
```

By default, ROSVENV mounts your home directory into the container and places you in the directory where you invoked `activateROS`. As long as you are only working in your home directory, you should not need to do much else. However, you can also customize the arguments passed to the container, for example if you want to mount another directory into it. To do so, you simply create a `docker_args` file at the root of the workspace and specify the options you need:

```text
# in docker_args
-v /my/data/dir:/data    # mounts /my/data/dir as /data inside the container
-v /my/music/dir:/music  # mounts /my/music/dir as /music inside the container
```

**Note**: There are no comments allowed inside this file.

To see what is possible, please refer to the CLI documentation of [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/).

To enable terminal colors inside the container, uncomment `force_color_prompt=yes` inside your `~/.bashrc`. 

### rosvenvStopContainer

Different from working with ROSVENV on your host system, leaving the container does not end its operation. Using `docker ps -a` you can see which containers are currently running. If you want to explicitly stop a container, you can use `rosvenvStopContainer [path/to/workspace]` to do so. This will invoke `docker rm -f` for the container for that workspace. Note that you don't have to pass the path to the workspace if you're somewhere in its directory tree.

### rosvenvRestartContainer

Sometimes it seems that containers loose access to the GPU after a longer time of operation. In that case it is necessary to restart the container. Leave the container using `deactivateROS` or `Ctrl+D` and run `rosvenvRestartContainer [path/to/workspace]`. This will stop the current running container for the workspace and restart it, pulling you back into it.

### rosvenvRebuildContainer

Sometimes you might change your `Dockerfile` and then need to rebuild your docker image. ROSVENV helps you with this with the `rosvenvRebuildContainer [path/to/workspace]` command. This command will only work if the workspace contains a `Dockerfile` *or* the workspace is set to launch the `rosvenv:latest` image. If this is the case, it will rebuild the image in question and (re-)start the container with the newly built image.

### Caveats

There a couple things to be aware of when using docker in combination with ROSVENV:
 - **THE BIGGEST ASSUMPTION**: ROSVENV assumes that your workspace is located inside **your** home directory, as your home is the one that will get mounted into the container. If you want to have it elsewhere, you need to mount the directory into the container using the `docker_args` files and `-v` option (see examples above). We don't think this is an atypical assumption to make, but think you should be aware of it.
 - ROSVENV uses the directory name of your workspace as name for the container it starts, independent of where on your machine the workspace is located. So `~/workspaces/my_ws` and `~/my_ws` will both look for a container called `my_ws`. Essentially you cannot/should not have duplicate workspace names running at the same time.
 - ROSVENV does not do any house-keeping. When you rebuild images this might abandon old images which need to be pruned. Use `docker images -a` to see a list of images on your system and their sizes. Use [`docker image prune`](https://docs.docker.com/reference/cli/docker/image/prune/) to remove these old versions.
 - Layering workspaces becomes more cumbersome with docker: To layer dockerized workspaces, use `activateROS` to activate your parent workspace and go inside its container. Inside the container use `createROSWS` to create the new child workspace. After it has been created, manually copy the parent's `docker_override` file to the child workspace. If the parent has a custom image it uses, aka a `Dockerfile` at its root, create the `docker_override` and write the image name into it. This saves you some disk space.
 - It was important for us to make the workflow with and without docker as similar as possible, which is why you don't have to repeat your last command after entering a container. However, the implementation of this feature is a bit sketchy: As you enter the container, the last command is written into `/tmp/COMMAND` inside the container. The shell inside the container reads this file and executes the command before it hands control over to you. Since there is only one container instance per workspace, multiple clients entering the container at the exact same moment can potentially lead to race-conditions. We have not experienced this so far, but have also not tried massive automized access to the container.
 - While `git` comes pre-installed in the `rosvenv` base image, it seems that double-tab completion does not work. We don't know why that is.

## Conclusion

We hope this tool will support you in managing ROS workspaces and network configurations, now and in the future. If you find any issues, please file them with the repository.
 
