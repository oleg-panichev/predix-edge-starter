#!/bin/sh
# Copyright (c) 2012-2016 General Electric Company. All rights reserved.
# The copyright to the computer software herein is the property of
# General Electric Company. The software may be used and/or copied only
# with the written permission of General Electric Company or in accordance
# with the terms and conditions stipulated in the agreement/contract
# under which the software has been supplied.

systemctl --user stop predixmachine.service
if [ $? -ne 0 ]; then
	echo "Could not stop the Predix Machine service."
	exit 1
else
	echo "Predix Machine service stopped."
fi
systemctl --user disable predixmachine.service
if [ $? -ne 0 ]; then
	echo "Could not disable the Predix Machine service."
	exit 1
else
	echo "Predix Machine service disabled."
fi
rm -f ~/.config/systemd/user/predixmachine.service
if [ $? -ne 0 ]; then
	echo "Could not remove the predixmachine.service configuration."
	exit 1
else
	echo "Removed the predixmachine.service configuration."
fi