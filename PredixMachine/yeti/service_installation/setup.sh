#!/bin/sh
# Copyright (c) 2012-2016 General Electric Company. All rights reserved.
# The copyright to the computer software herein is the property of
# General Electric Company. The software may be used and/or copied only
# with the written permission of General Electric Company or in accordance
# with the terms and conditions stipulated in the agreement/contract
# under which the software has been supplied.

# Create the systemd config into the systemd user directory
echo "Root privileges are required to modify the /etc/systemd/user.conf Service Manager configuration file."
sudo -v || exit
yeti_dir="$(dirname "$0")/.."
yeti_dir=$(readlink -f "$yeti_dir")

case "$yeti_dir" in
	*\ * )
		echo "Path to the yeti directory contains spaces. This is bad practice. Please remove these spaces before continuing."
		echo "$yeti_dir"
		exit 1
		;;
esac

if [ ! -f /etc/systemd/user.conf ]; then
	echo "Failure: /etc/systemd/ directory not found. Is systemd installed on this system?"
	exit 1
fi

if [ ! -d ~/.config/systemd/user ]; then
	mkdir ~/.config/systemd
	mkdir ~/.config/systemd/user
fi

if [ -f ~/.config/systemd/user/predixmachine.service ]; then
	echo "Predix Machine service already exists at ~/.config/systemd/user/predixmachine.service. This will be overwritten.  Remove this before continuing."
	exit 1
fi

# Create the predixmachine.service configuration file
printf "[Unit]\n\
Description=Predix Machine service for monitoring and updating the Predix Machine container\n\
\n\
[Service]\n\
Type=simple\n\
ExecStart=$yeti_dir/start_yeti.sh\n\
ExecStop=$yeti_dir/stop_yeti.sh\n\
Restart=on-failure\n\
RestartSec=10\n\
\n\
[Install]\n\
WantedBy=default.target\n" > ~/.config/systemd/user/predixmachine.service

# Modify the predixmachine.service config with the path to the start and stop scripts
echo "Service file created in ~/.config/systemd/user/predixmachine.service."

# Add the current path to the systemd user.conf.  This will add to whatever is there already.
lineNum=$(awk '/DefaultEnvironment=/{print NR; exit}' /etc/systemd/user.conf)
if [ x"$lineNum" != x"" ]; then
	defaultEnv=$(sed -n "${lineNum}p" /etc/systemd/user.conf)
	defaultEnv=$(echo $defaultEnv | tr "=" "\n")
	pathEntry=$(echo $defaultEnv | awk '{print $2}')
	pathEntry="${pathEntry%\"}"
	pathEntry="${pathEntry#\"}"
	tokenizedUserConfPath=$(echo $pathEntry | tr ":" "\n")
fi
tokenizedPath=$(echo $PATH | tr ":" "\n")
for entry in $tokenizedPath; do
	match=false
	for userConfEntry in $tokenizedUserConfPath; do
		if [ x"$userConfEntry" = x"$entry" ]; then
			match=true
			continue
		fi
	done
	if [ $match = false ]; then
		pathEntry="$pathEntry:$entry"
	fi
done
if [ x"$lineNum" != x"" ]; then
	sudo sed -i -e s~.*DefaultEnvironment=.*~DefaultEnvironment="\""$pathEntry"\""~g /etc/systemd/user.conf
else
	printf "DefaultEnvironment="\""$pathEntry"\"\\n"" | sudo tee -a /etc/systemd/user.conf
fi
echo "Default path added to the /etc/systemd/user.conf configuration."

# Enable the service at boot
systemctl --user daemon-reload
if [ $? -ne 0 ]; then
	echo "Systemctl daemon reload failed."
	exit 1
else
	echo "Daemon configuration reloaded."
fi
systemctl --user enable predixmachine.service
if [ $? -ne 0 ]; then
	echo "Predix Machine service could not be enabled at boot."
else
	echo "Predix Machine service enabled at boot."
fi
echo "Predix Machine service installed. To start the service run: \"systemctl --user start predixmachine\"  To stop the service run: \"systemctl --user stop predixmachine\""