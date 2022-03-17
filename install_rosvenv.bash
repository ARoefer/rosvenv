#!/bin/bash
cp -f rosvenv.bash "${HOME}/.rosvenv.bash"

if [ "$( type -t createROSWS )" != "function" ]; then
	printf "\n# ROSVENV\nsource ~/.rosvenv.bash\n" >> "${HOME}/.bashrc"
	echo "Added sourcing of ~/.rosvenv.bash to your ~/.bashrc"
fi

source "${HOME}/.rosvenv.bash"
echo "ROSVENV should now be usable!"
