
ln -sf /usr/lib/jvm/java-8-openjdk/bin/keytool /usr/bin/keytool
dir=`pwd`
export PREDIX_MACHINE_HOME=/home/root/PredixMachine
cd $PREDIX_MACHINE_HOME/machine/bin/predix
nohup ./predixmachine clean > $PREDIX_MACHINE_HOME/logs/machine/machine.log 2> $PREDIX_MACHINE_HOME/logs/machine/machine.err < /dev/null &
cd $dir
