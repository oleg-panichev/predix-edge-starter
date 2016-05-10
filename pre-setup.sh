#!/bin/bash
set -e
# Predix Dev Bootstrap Script
# Authors: GE SDLP 2015
#
scriptRootDir=$(dirname $0)
# Be sure to set all your variables in the variables.sh file before you run quick start!
source "$scriptRootDir/scripts/variables.sh"
source "$scriptRootDir/scripts/error_handling_funcs.sh"
source "$scriptRootDir/scripts/files_helper_funcs.sh"
source "$scriptRootDir/scripts/curl_helper_funcs.sh"

pathFromCallingScript=$(dirname $0)


if [[ "$#" -gt 0 ]] ; then
	while [ "$1" != "" ]; do
    case $1 in
        -p | --password )       						shift
                                						CF_PASSWORD=$1
                                						;;
        -path | --pathFromCallingScript )   shift
																						pathFromCallingScript=$1
                                						;;
				-delete | --deleteTheAppsAndServices )   ./scripts/cleanup.sh
																						exit
																		        ;;
        -h | --help )           						echo "usage: pre-setup.sh [[-p password ] [-f pathCallingFromToHere]] | [-h]"
                                						exit
                                						;;
        * )                    						 echo "usage: pre-setup.sh [[-p password ] [-f pathCallingFromToHere]] | [-h]"
                                					exit 1
    esac
    shift
	done
fi



# Trap ctrlc and exit if encountered

trap "trap_ctrlc" 2

# Clean input for machine type and tag, no spaces allowed

ASSET_TYPE="$(echo -e "${ASSET_TYPE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
ASSET_TYPE_NOSPACE=${ASSET_TYPE// /_}
ASSET_TAG="$(echo -e "${ASSET_TAG}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
ASSET_TAG_NOSPACE=${ASSET_TAG// /_}

# Creating a logfile if it doesn't exist

touch "$scriptRootDir/quickstartlog.log"

# Login into Cloud Foundy using the user input or password entered on request
userSpace="`cf t | grep Space | awk '{print $2}'`"
if [[ "$userSpace" != "$CF_SPACE" ]] ; then
	__append_new_line_log "# quickstart.sh script started! #" "$scriptRootDir"
	echo -e "Welcome to the Predix Quick start script!\n"
	echo -e "Be sure to set all your variables in the variables.sh file before you run quick start!\n"
	echo -e " ### Logging in to Cloud Foundry ### \n"

	if [[ "$#" -eq 1 ]] ; then
		__append_new_line_log "Using the provided authentication passed to the script..." "$scriptRootDir"
		CF_PASSWORD="$1"
	else
		echo "ENTER YOUR PASSWORD NOW followed by ENTER"
		read -s CF_PASSWORD
	fi

	__append_new_line_log "Attempting to login user \"$CF_USERNAME\" to host \"$CF_HOST\" Cloud Foundry. Space: \"$CF_SPACE\" Org: \"$CF_ORG\"" "$scriptRootDir"
	if cf login -a $CF_HOST -u $CF_USERNAME -p $CF_PASSWORD -o $CF_ORG -s $CF_SPACE --skip-ssl-validation; then
		__append_new_line_log "Successfully logged into CloudFoundry" "$scriptRootDir"
	else
		__error_exit "There was an error logging into CloudFoundry. Is the password correct?" "$scriptRootDir"
	fi
fi

# Push a test app to get VCAP information for the Predix Services
tempAppExists=$(__does_app_exist $TEMP_APP)
#echo "tempAppExists=$tempAppExists"
if [ $tempAppExists -eq "1" ]; then
	echo -e "$TEMP_APP exists already ...\n"
else
	echo -e "Pushing $TEMP_APP to initially create Predix Microservices ...\n"
	echo -e "cf push $TEMP_APP -f $scriptRootDir/testapp/manifest.yml --no-start --random-route -t 180"
	if cf push $TEMP_APP -f $scriptRootDir/testapp/manifest.yml --no-start --random-route -t 180; then
		__append_new_line_log "Temp app successfully pushed to CloudFoundry!" "$scriptRootDir"
	else
		__error_exit "There was an error pushing the TEMP_APP to CloudFoundry..." "$scriptRootDir"
	fi
fi

# Create instance of Predix UAA Service
echo -e "cf cs $UAA_SERVICE_NAME $UAA_PLAN $UAA_INSTANCE_NAME -c "{\"adminClientSecret\":\"*****\"}""
if cf cs $UAA_SERVICE_NAME $UAA_PLAN $UAA_INSTANCE_NAME -c "{\"adminClientSecret\":\"$UAA_ADMIN_SECRET\"}"; then
	__append_new_line_log "UAA Service instance successfully created!\n" "$scriptRootDir"
else
	__append_new_line_log "Couldn't create UAA service. Retrying..." "$scriptRootDir"
	echo -e "cf cs $UAA_SERVICE_NAME $UAA_PLAN $UAA_INSTANCE_NAME -c "{\"adminClientSecret\":\"*****\"}""
	if cf cs $UAA_SERVICE_NAME $UAA_PLAN $UAA_INSTANCE_NAME -c "{\"adminClientSecret\":\"$UAA_ADMIN_SECRET\"}"; then
		__append_new_line_log "UAA Service instance successfully created!" "$scriptRootDir"
	else
		__error_exit "Couldn't create UAA service instance..." "$scriptRootDir"
	fi
fi

# Bind Temp App to UAA instance
echo -e "cf bs $TEMP_APP $UAA_INSTANCE_NAME"
if cf bs $TEMP_APP $UAA_INSTANCE_NAME; then
	__append_new_line_log "UAA instance successfully binded to TEMP_APP!" "$scriptRootDir"
else
	echo -e "cf bs $TEMP_APP $UAA_INSTANCE_NAME"
	if cf bs $TEMP_APP $UAA_INSTANCE_NAME; then
    __append_new_line_log "UAA instance successfully binded to TEMP_APP!" "$scriptRootDir"
  else
    __error_exit "There was an error binding the UAA service instance to the TEMP_APP!" "$scriptRootDir"
  fi
fi

# Get the UAA enviorment variables (VCAPS)
if trustedIssuerID=$(cf env $TEMP_APP | grep predix-uaa* | grep issuerId*| awk 'BEGIN {FS=":"}{print "https:"$3}' | awk 'BEGIN {FS="\","}{print $1}' ); then
	echo "trustedIssuerID : $trustedIssuerID"
	__append_new_line_log "trustedIssuerID copied from enviromental variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting the UAA trustedIssuerID..." "$scriptRootDir"
fi

if uaaURL=$(cf env $TEMP_APP | grep predix-uaa* | grep uri*| awk 'BEGIN {FS=":"}{print "https:"$3}' | awk 'BEGIN {FS="\","}{print $1}' ); then
	__append_new_line_log "UAA URL copied from enviromental variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting the UAA URL..." "$scriptRootDir"
fi


# Create instance of Predix TimeSeries Service
echo -e "cs $TIMESERIES_SERVICE_NAME $TIMESERIES_SERVICE_PLAN $TIMESERIES_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}""
if cf cs $TIMESERIES_SERVICE_NAME $TIMESERIES_SERVICE_PLAN $TIMESERIES_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}"; then
	__append_new_line_log "Predix TimeSeries Service instance successfully created!" "$scriptRootDir"
else
	echo -e "cs $TIMESERIES_SERVICE_NAME $TIMESERIES_SERVICE_PLAN $TIMESERIES_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}""
	if cf cs $TIMESERIES_SERVICE_NAME $TIMESERIES_SERVICE_PLAN $TIMESERIES_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}"; then
    __append_new_line_log "Predix TimeSeries Service instance successfully created!" "$scriptRootDir"
  else
    __error_exit "Couldn't create Predix TimeSeries service instance..." "$scriptRootDir"
  fi
fi

# Bind Temp App to TimeSeries Instance
echo -e "cf bs $TEMP_APP $TIMESERIES_INSTANCE_NAME"
if cf bs $TEMP_APP $TIMESERIES_INSTANCE_NAME; then
	__append_new_line_log "Predix TimeSeries instance successfully binded to TEMP_APP!" "$scriptRootDir"
else
	echo -e "cf bs $TEMP_APP $TIMESERIES_INSTANCE_NAME"
	if cf bs $TEMP_APP $TIMESERIES_INSTANCE_NAME; then
    __append_new_line_log "Predix TimeSeries instance successfully binded to TEMP_APP!" "$scriptRootDir"
  else
    __error_exit "There was an error binding the Predix TimeSeries service instance to the $TEMP_APP!" "$scriptRootDir"
  fi
fi


# Get the Zone ID and URIs from the enviroment variables (for use when querying and ingesting data)

if TIMESERIES_ZONE_ID=$(cf env $TEMP_APP | grep -m 1 zone-http-header-value | sed 's/"zone-http-header-value": "//' | sed 's/",//' | tr -d '[[:space:]]'); then
	echo "TIMESERIES_ZONE_ID : $TIMESERIES_ZONE_ID"
	__append_new_line_log "TIMESERIES_ZONE_ID copied from enviromental variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting TIMESERIES_ZONE_ID..." "$scriptRootDir"
fi

if TIMESERIES_INGEST_URI=$(cf env $TEMP_APP | grep wss: | grep -m 1 uri | sed 's/"uri": "//' | sed 's/",//' | tr -d '[[:space:]]'); then
	echo "TIMESERIES_INGEST_URI : $TIMESERIES_INGEST_URI"
	__append_new_line_log " TIMESERIES_INGEST_URI copied from enviromental variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting TIMESERIES_INGEST_URI..." "$scriptRootDir"
fi

if TIMESERIES_QUERY_URI=$(cf env $TEMP_APP | grep -m 2 uri | grep https | sed 's/"uri": "//' | sed 's/",//' | tr -d '[[:space:]]'); then
	__append_new_line_log "TIMESERIES_QUERY_URI copied from enviromental variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting TIMESERIES_QUERY_URI..." "$scriptRootDir"
fi

# Create instance of Predix Asset Service
echo -e "cf cs $ASSET_SERVICE_NAME $ASSET_SERVICE_PLAN $ASSET_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}""
if cf cs $ASSET_SERVICE_NAME $ASSET_SERVICE_PLAN $ASSET_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}"; then
	__append_new_line_log "Predix Asset Service instance successfully created!" "$scriptRootDir"
else
	echo -e "cf cs $ASSET_SERVICE_NAME $ASSET_SERVICE_PLAN $ASSET_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}""
	if cf cs $ASSET_SERVICE_NAME $ASSET_SERVICE_PLAN $ASSET_INSTANCE_NAME -c "{\"trustedIssuerIds\":[\"$trustedIssuerID\"]}"; then
    __append_new_line_log "Predix Asset Service instance successfully created!" "$scriptRootDir"
  else
    __error_exit "Couldn't create Predix Asset service instance..." "$scriptRootDir"
  fi
fi

# Bind Temp App to Asset Instance
echo -e "cf bs $TEMP_APP $ASSET_INSTANCE_NAME"
if cf bs $TEMP_APP $ASSET_INSTANCE_NAME; then
	__append_new_line_log "Predix Asset instance successfully binded to $TEMP_APP!" "$scriptRootDir"
else
	echo -e "cf bs $TEMP_APP $ASSET_INSTANCE_NAME"
	if cf bs $TEMP_APP $ASSET_INSTANCE_NAME; then
		__append_new_line_log "Predix Asset instance successfully binded to $TEMP_APP!" "$scriptRootDir"
	else
		__error_exit "There was an error binding the Predix Asset service instance to the $TEMP_APP!" "$scriptRootDir"
	fi
fi

# Get the Zone ID from the enviroment variables (for use when querying Asset data)

if ASSET_ZONE_ID=$(cf env $TEMP_APP | grep -m 1 http-header-value | sed 's/"http-header-value": "//' | sed 's/",//' | tr -d '[[:space:]]'); then
	__append_new_line_log "ASSET_ZONE_ID copied from environment variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting ASSET_ZONE_ID..." "$scriptRootDir"
fi

# Create client ID for generic use by applications - including timeseries and asset scope

__createUaaClient "$uaaURL" "$TIMESERIES_ZONE_ID" "$ASSET_SERVICE_NAME" "$ASSET_ZONE_ID"

# Create a new user account

__addUaaUser "$uaaURL"

# Get the Asset URI and generate Asset body from the enviroment variables (for use when querying and posting data)

if assetURI=$(cf env $TEMP_APP | grep uri*| grep asset* | awk 'BEGIN {FS=":"}{print "https:"$3}' | awk 'BEGIN {FS="\","}{print $1}'); then
	__append_new_line_log "assetURI copied from environment variables!" "$scriptRootDir"
else
	__error_exit "There was an error getting assetURI..." "$scriptRootDir"
fi

if assetPostBody=$(printf '[{"uri": "%s", "tag": "%s", "description": "%s"}]%s' "/$ASSET_TYPE_NOSPACE/$ASSET_TAG_NOSPACE" "$ASSET_TAG_NOSPACE" "$ASSET_DESCRIPTION"); then
	__append_new_line_log "assetPostBody ok!" "$scriptRootDir"
else
	__error_exit "There was an error getting assetPostBody..." "$scriptRootDir"
fi

#if cd $scriptRootDir/Asset-Post-Util-OS; then
#	__append_new_line_log "Calling the correct Asset-Post-Util depending on the OS" "$scriptRootDir"
#else
#	__error_exit "Error changing directory" "$scriptRootDir"
#fi

# Call the correct Asset-Post-Util depending on the OS in order to post the Asset data

if [ "$(uname -s)" == "Darwin" ]
then
	__append_new_line_log "Posting asset data to Predix Asset using OSx" "$scriptRootDir"
	$scriptRootDir/Asset-Post-Util-OS/OSx/Asset-Post-Util $uaaURL $assetURI/$ASSET_TYPE_NOSPACE $UAA_CLIENTID_GENERIC $UAA_CLIENTID_GENERIC_SECRET $ASSET_ZONE_ID "$assetPostBody"
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]
then
	__append_new_line_log "Posting asset data to Predix Asset using Linux" "$scriptRootDir"
	$scriptRootDir/Asset-Post-Util-OS/Linux/Asset-Post-Util $uaaURL $assetURI/$ASSET_TYPE_NOSPACE $UAA_CLIENTID_GENERIC $UAA_CLIENTID_GENERIC_SECRET $ASSET_ZONE_ID "$assetPostBody"
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]
then
	# First unzip the file to get the exe
  unzip -o Asset-Post-Util.zip
	__append_new_line_log "Posting asset data to Predix Asset using Windows" "$scriptRootDir"
  $scriptRootDir/Asset-Post-Util-OS/Win/Asset-Post-Util.exe $uaaURL $assetURI/$ASSET_TYPE_NOSPACE $UAA_CLIENTID_GENERIC $UAA_CLIENTID_GENERIC_SECRET $ASSET_ZONE_ID "$assetPostBody"
fi

# __append_new_line_log "Deleting the $TEMP_APP" "$scriptRootDir"
# if cf d $TEMP_APP -f -r; then
# 	__append_new_line_log "Successfully deleted $TEMP_APP" "$scriptRootDir"
# else
# 	__append_new_line_log "Failed to delete $TEMP_APP. Retrying..." "$scriptRootDir"
# 	if cf d $TEMP_APP -f -r; then
# 		__append_new_line_log "Successfully deleted $TEMP_APP" "$scriptRootDir"
# 	else
# 		__append_new_line_log "Failed to delete $TEMP_APP. Last attempt..." "$scriptRootDir"
# 		if cf d $TEMP_APP -f -r; then
# 			__append_new_line_log "Successfully deleted $TEMP_APP" "$scriptRootDir"
# 		else
# 			__error_exit "Failed to delete $TEMP_APP. Giving up" "$scriptRootDir"
# 		fi
# 	fi
# fi

# Call the correct zip depending on the OS... and get the base64 of the UAA base64ClientCredential
MYGENERICS_SECRET=$(echo -ne $UAA_CLIENTID_GENERIC:$UAA_CLIENTID_GENERIC_SECRET | base64)
# Build our application from the 'predix-nodejs-starter' repo, passing it our MS instances
echo "param string $GIT_PREDIX_NODEJS_STARTER_URL $FRONT_END_APP_NAME $UAA_CLIENTID_GENERIC $MYGENERICS_SECRET $uaaURL $TIMESERIES_QUERY_URI $TIMESERIES_ZONE_ID $assetURI $ASSET_TYPE_NOSPACE $ASSET_TAG_NOSPACE $ASSET_ZONE_ID"
$scriptRootDir/scripts/build-basic-app.sh "$GIT_PREDIX_NODEJS_STARTER_URL" "$FRONT_END_APP_NAME" "$UAA_CLIENTID_GENERIC" "$MYGENERICS_SECRET" "$uaaURL" "$TIMESERIES_QUERY_URI" "$TIMESERIES_ZONE_ID" "$assetURI" "$ASSET_TYPE_NOSPACE" "$ASSET_TAG_NOSPACE" "$ASSET_ZONE_ID"

if [ "$?" = "0" ]; then
	__append_new_line_log "Successfully built and pushed the front end application" "$scriptRootDir"
else
	__append_new_line_log "Build or Push of Basic Application Failed" "$scriptRootDir" 1>&2
	exit 1
fi

if cf start $FRONT_END_APP_NAME; then
	printout="$FRONT_END_APP_NAME started!"
	__append_new_line_log "$printout" "$scriptRootDir" 1>&2
else
	__error_exit "Couldn't start $FRONT_END_APP_NAME" "$scriptRootDir"
fi


__append_new_line_log "Setting predix machine configurations" "$scriptRootDir"
rm -rf $scriptRootDir/PredixMachine
unzip $scriptRootDir/PredixMachine.zip -d $scriptRootDir/PredixMachine
$scriptRootDir/scripts/machineconfig.sh $pathFromCallingScript/scripts $trustedIssuerID $TIMESERIES_INGEST_URI $TIMESERIES_ZONE_ID

echo "" > $scriptRootDir/config.txt
echo "**********************SUCCESS*************************" >> $scriptRootDir/config.txt
echo "echoing properties from $scriptRootDir/config.txt"  >> $scriptRootDir/config.txt
echo "What did we do:"  >> $scriptRootDir/config.txt
echo "We created a Basic Predix App with Predix Machine integration"  >> $scriptRootDir/config.txt
echo "Installed UAA with a client_id/secret (for your app) and a user/password (for your users to log in to your app)" >> $scriptRootDir/config.txt
echo "Installed Time Series and added time series scopes as client_id authorities" >> $scriptRootDir/config.txt
echo "Installed Asset and added asset scopes as client_id authorities" >> $scriptRootDir/config.txt
echo "Installed a simple front-end named $FRONT_END_APP_NAME and updated the property files and manifest.yml with UAA, Time Series and Asset info" >> $scriptRootDir/config.txt
echo "Installed Predix Machine and updated the property files with UAA and Time Series info" >> $scriptRootDir/config.txt
echo "" >> $scriptRootDir/config.txt
echo "Predix Dev Bootstrap Configuration" >> $scriptRootDir/config.txt
echo "Authors SDLP v1 2015" >> $scriptRootDir/config.txt
echo "UAA URL: $uaaURL" >> $scriptRootDir/config.txt
echo "UAA Admin Client ID: admin" >> $scriptRootDir/config.txt
echo "UAA Admin Client Secret: $UAA_ADMIN_SECRET" >> $scriptRootDir/config.txt
echo "UAA Generic Client ID: $UAA_CLIENTID_GENERIC" >> $scriptRootDir/config.txt
echo "UAA Generic Client Secret: $UAA_CLIENTID_GENERIC_SECRET" >> $scriptRootDir/config.txt
echo "UAA User ID: $UAA_USER_NAME" >> $scriptRootDir/config.txt
echo "UAA User PASSWORD: $UAA_USER_PASSWORD" >> $scriptRootDir/config.txt
echo "TimeSeries Ingest URL:  $TIMESERIES_INGEST_URI" >> $scriptRootDir/config.txt
echo "TimeSeries Query URL:  $TIMESERIES_QUERY_URI" >> $scriptRootDir/config.txt
echo "TimeSeries ZoneID: $TIMESERIES_ZONE_ID" >> $scriptRootDir/config.txt
echo "Asset URL:  $assetURI" >> $scriptRootDir/config.txt
echo "Asset Zone ID: $ASSET_ZONE_ID" >> $scriptRootDir/config.txt
echo "Front end App Name URL: https://`cf a | grep \"$FRONT_END_APP_NAME\" | awk '{print $6}'`" >> $scriptRootDir/config.txt
echo "" >> $scriptRootDir/config.txt
echo -e "You can execute 'cf env "$FRONT_END_APP_NAME"' to view info about your front-end app, UAA, Asset, and Time Series" >> $scriptRootDir/config.txt
echo -e "In your web browser, navigate to your front end application endpoint" >> $scriptRootDir/config.txt
echo -e "PredixMachine is configured and ready to launch using script at: $pathFromCallingScript/PredixMachine/machine/bin/predix/predixmachine" >> $scriptRootDir/config.txt
echo -e "pre-setup completed....."

cat $scriptRootDir/config.txt
