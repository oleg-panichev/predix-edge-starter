#!/bin/bash
# Copyright (c) 2012-2016 General Electric Company. All rights reserved.
# The copyright to the computer software herein is the property of
# General Electric Company. The software may be used and/or copied only
# with the written permission of General Electric Company or in accordance
# with the terms and conditions stipulated in the agreement/contract
# under which the software has been supplied.

# Method to write to the console output as well as a log file
writeConsoleLog () {
	echo "$(date +"%m/%d/%y %H:%M:%S") $1"
	echo "$(date +"%m/%d/%y %H:%M:%S") $1" >> "$LOG"
}

# Stops the mbsa process and shuts down the container
killmbsa () {
	sh "$PREDIXHOME/mbsa/bin/mbsa_stop.sh" >> "$LOG" 2>&1 || code=$?
	if [ -z "$code" ] || [ $code -eq 0 ]; then
		# code is an empty string unless mbsa throws an error. Empty string is equivalent to exit code 0
		writeConsoleLog "MBSA stopped, container shutting down..."
	elif [ $code -eq 2 ]; then
		# 2 is the exit code mBSA sends when attempting to stop an already stopped container
		writeConsoleLog "MBSA is shut down, no container was running."
	else
		writeConsoleLog "MBSA failed to shut down the container. Attempting to forcibly close..."
	fi
	mbsapid=$(ps ax | grep mbsae.core | grep -v grep | awk '{ print $1 }')
	for mbsaprcs in $mbsapid; do
		kill -9 $mbsaprcs
		echo -n "Killed mbsa (process $mbsaprcs)"
	done
}

# A trap method that's called on install completion.  Writes the status file
finish () {
	writeConsoleLog "$message"
	if [ $errorcode -eq 0 ]; then
		printf "{\n\t\"status\" : \"$status\",\n\t\"message\" : \"$message\"\n}\n" > "$AIRSYNC/$ZIPNAME.json"
	else
		printf "{\n\t\"status\" : \"$status\",\n\t\"errorcode\" : $errorcode,\n\t\"message\" : \"$message\"\n}\n" > "$AIRSYNC/$ZIPNAME.json"
	fi
	# Start the container before exiting
	nohup sh "$PREDIXHOME/mbsa/bin/mbsa_start.sh" > /dev/null 2>&1 &
}
trap finish EXIT

prosystkey () {
	# Prosyst has a limited key that must not be replaced by the installation
	writeConsoleLog "Backing up Prosyst limited key."
	cp -Rp "$PREDIXHOME/machine/bin/vms/domain.crp" "$UPDATEDIR/machine/bin/vms/domain.crp">>"$LOG" 2>&1
	if [ ! $? -eq 0 ]; then
		message="Prosyst limited key could not be inserted into the update package."
		errorcode="4"
		status="failure"
		exit 1
	fi
}

rollback () {
	directory=$1
	writeConsoleLog "Update unsuccessful. Attempting to rollback."
	if [ -d "$PREDIXHOME/$directory" ]; then
		rm -r "$PREDIXHOME/$directory/">>"$LOG" 2>&1
	fi
	mv "$PREDIXHOME/$directory.old/" "$PREDIXHOME/$directory/">>"$LOG" 2>&1
	if [ $? -eq 0 ]; then
		writeConsoleLog "Rollback successful."
	else
		writeConsoleLog "Rollback unsuccessful."
	fi
}

# Performs the application install.  Uses the $application environmental variable set to determine the application to update
applicationInstall () {
	# Shutdown container for update
	echo "$(date +"%m/%d/%y %H:%M:%S") ##########################################################################">> "$LOG"
	echo "$(date +"%m/%d/%y %H:%M:%S") #                 Shutting down container for update                     #">> "$LOG"
	echo "$(date +"%m/%d/%y %H:%M:%S") ##########################################################################">> "$LOG"
	killmbsa
	while ps aux | grep mbsae.core | grep -v grep > /dev/null; do
		writeConsoleLog "Error exiting mBSA processes, will try again in 1 minute"
		sleep 60
	done
	prosystkey
	writeConsoleLog "Updating the $application directory."
	if [ -d "$PREDIXHOME/$application" ]; then
		writeConsoleLog "Updating $application application. Backup of current application stored in $application.old."
		if [ -d "$PREDIXHOME/$application.old" ]; then
			writeConsoleLog "Updating $application.old application backup to revision before this update."
			rm -r "$PREDIXHOME/$application.old/">>"$LOG" 2>&1
			if [ $? -eq 0 ]; then
				writeConsoleLog "Previous $application.old removed."
			else
				message="Previous $application.old could not be removed."
				errorcode="1"
				status="failure"
				exit 1
			fi
		fi
		mv "$PREDIXHOME/$application/" "$PREDIXHOME/$application.old/">>"$LOG" 2>&1
		if [ $? -eq 0 ]; then
			writeConsoleLog "The $application application backup created as $application.old."
		else
			message="The $application application could not be renamed to $application.old."
			errorcode="2"
			status="failure"
			exit 2
		fi
	fi
	mv "$UPDATEDIR/$application/" "$PREDIXHOME/$application/">>"$LOG" 2>&1

	if [ $? -eq 0 ]; then
		chmod +x "$PREDIXHOME/$application/bin/predix/predix$application"
		message="The $application application was updated successfully."
		errorcode="0"
		status="success"
		exit 0
	else
		message="The $application application could not be updated."
		errorcode="3"
		status="failure"
		# Attempt a rollback
		rollback "$application"
		exit 3
	fi
}

# This is the status that will be written if the script exits unexpectedly
status="failure"
errorcode="1"
message="Installation failed unexpectedly."

# This install script will be called by yeti which will provide three arguements
# The first argument is the Predix Home directory which is the directory to the 
# Predix Machine container
# The second arguement is the path to the application directory.  This contains 
# the new application to be installed.
# The third arguement is the name of the zip.  This must be used to create
# the JSON file to verify the status of the installation.  The JSON must be
# placed in the appdata/airsync directory with the name $ZIPNAME.json

# Updating the application proceeds as follows:
# 1. Make a backup of previous application
# 2. Add new application
# 3. Return an error code or 0 for success
PREDIXHOME=$1
UPDATEDIR=$2
ZIPNAME=$3
DATE=`date +%m%d%y%H%M%S`
# Replace this with the name of your application directory
application=machine
LOG=$PREDIXHOME/logs/installations/install_$application${DATE}.txt
AIRSYNC=$PREDIXHOME/appdata/airsync
# Update the $application application by removing any old backups, renaming the
# current installed application to $application.old, and adding the updated
# application
applicationInstall