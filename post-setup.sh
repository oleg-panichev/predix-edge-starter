#!/bin/bash
set -e
# Predix Dev Bootstrap Script
# Authors: GE SDLP 2015
#
# Be sure to set all your variables in the variables.sh file before you run quick start!

scriptRootDir=$(dirname $0)
source "$scriptRootDir/scripts/variables.sh"
source "$scriptRootDir/scripts/error_handling_funcs.sh"
source "$scriptRootDir/scripts/files_helper_funcs.sh"
source "$scriptRootDir/scripts/curl_helper_funcs.sh"


CWD="`pwd`"
cd ../predix-edge-starter
if [ "$(uname -s)" == "Darwin" ]
then
	cp $scriptRootDir/scripts/pm_background.sh $PREDIXMACHINEHOME/machine/bin/predix
	__append_new_line_log "Zipping up the configured Predix Machine..." "$scriptRootDir"
	rm -rf $scriptRootDir/PredixMachineContainer.zip
	if zip -r $scriptRootDir/PredixMachineContainer.zip $PREDIXMACHINEHOME > zipoutput.log; then
		__append_new_line_log "Zipped up the configured Predix Machine and storing in $scriptRootDir/PredixMachineContainer.zip" "$scriptRootDir"
		scp $scriptRootDir/PredixMachineContainer.zip $TARGETDEVICEUSER@$TARGETDEVICEIP:PredixMachineContainer.zip
	else
		__error_exit "Failed to zip up PredixMachine_16.1.0" "$scriptRootDir"
	fi
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]
	__append_new_line_log "Zipping up the configured Predix Machine..." "$scriptRootDir"
	rm -rf $scriptRootDir/PredixMachineContainer.zip
	if zip -r $scriptRootDir/PredixMachineContainer.zip $PREDIXMACHINEHOME > zipoutput.log; then
		__append_new_line_log "Zipped up the configured Predix Machine and storing in $scriptRootDir/PredixMachineContainer.zip" "$scriptRootDir"
		scp $scriptRootDir/PredixMachineContainer.zip $TARGETDEVICEUSER@$TARGETDEVICEIP:PredixMachineContainer.zip
	else
		__error_exit "Failed to zip up PredixMachine_16.1.0" "$scriptRootDir"
	fi
then
	__append_new_line_log "You must manually zip PredixMachine_16.1.0 to port it to the Edge Device" "$scriptRootDir"
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]
then
	__append_new_line_log "You must manually zip of PredixMachine_16.1.0 to port it to the Edge Device" "$scriptRootDir"
fi

echo "" >> $scriptRootDir/config.txt
echo "Post Setup Configuration" >> $scriptRootDir/config.txt
echo "What did we do:"  >> $scriptRootDir/config.txt
echo "We zipped up the machine container with the device specific changes"  >> $scriptRootDir/config.txt
echo "If your device is hooked up and at the IP you mentioned, we copied the zip/tar file to the device"  >> $scriptRootDir/config.txt
echo "Now you can uzip/untar the file and launch Predix Machine.  It will send data to Predix Time Series in the cloud and you can view it in the Basic UI."  >> $scriptRootDir/config.txt
echo "Edge Device: ssh $TARGETDEVICEUSER@$TARGETDEVICEIP"  >> $scriptRootDir/config.txt



cat $scriptRootDir/config.txt
