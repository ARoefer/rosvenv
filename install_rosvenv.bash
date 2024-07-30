#!/bin/bash
cp -f $(realpath "$(dirname "$BASH_SOURCE")")/rosvenv.bash "${HOME}/.rosvenv.bash"
echo "" >> "${HOME}/.rosvenv.bash"
cat $(realpath "$(dirname "$BASH_SOURCE")")/rosvenv_docker.bash >> "${HOME}/.rosvenv.bash"

if [ "$( type -t createROSWS )" != "function" ]; then
	printf "\n# ROSVENV\nsource ~/.rosvenv.bash\n" >> "${HOME}/.bashrc"
	export ROSVENV_ROOT="$(realpath "$(dirname "$BASH_SOURCE")")"
	echo "export ROSVENV_ROOT=$ROSVENV_ROOT" >> "${HOME}/.bashrc"
	echo "Added sourcing of ~/.rosvenv.bash to your ~/.bashrc"
fi

source "${HOME}/.rosvenv.bash"

if ! _rosvenv_precheck; then
	if rosvenv_has_docker; then
		echo "You do not seem to have ROS installed, but docker."

		if rosvenv_docker_image_exists $ROSVENV_DEFAULT_DOCKER_IMAGE; then
			read -p "The ROSVENV image is already present. Do you want to rebuild it? [y/n]: " confirm
		else
			read -p "Do you want to use ROSVENV in docker? [y/n]: " confirm
		fi

		if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
			rosvenv_docker_build_container
		else
			echo "Okay, you can (re-)build the container at a later time."
		fi
	else
		echo "You have neither ROS nor docker installed. You will not be able to run ROS."
	fi
fi

echo "ROSVENV should now be usable!"
