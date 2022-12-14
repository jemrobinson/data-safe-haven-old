#! /bin/bash

# Require one arguments: config file identifier
if [ $# -ne 1 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
PACKAGE_NAME=$1

# Ensure that the config file exists
CONFIG_FILE="/opt/build/${PACKAGE_NAME}.debinfo"
if [ ! -e $CONFIG_FILE ]; then
    echo "FATAL: Config file could not be loaded from $CONFIG_FILE"
    exit 2
fi

# Parse the config file
PACKAGE_HASH=$(grep "hash:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')
PACKAGE_VERSION=$(grep "version:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')
PACKAGE_DEBFILE=$(grep "debfile:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION|/$PACKAGE_VERSION/")
PACKAGE_REMOTE=$(grep "remote:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION|/$PACKAGE_VERSION/" | sed "s/|DEBFILE|/$PACKAGE_DEBFILE/")

# Ensure that all required variables have been set
if [ ! "$PACKAGE_DEBFILE" ]; then exit 3; fi
if [ ! "$PACKAGE_HASH" ]; then exit 3; fi
if [ ! "$PACKAGE_NAME" ]; then exit 3; fi
if [ ! "$PACKAGE_REMOTE" ]; then exit 3; fi

# Download and verify the .deb file
echo "Downloading and verifying deb file..."
wget -nv $PACKAGE_REMOTE -P /opt/build/
ls -alh /opt/build/${PACKAGE_DEBFILE}
echo "$PACKAGE_HASH /opt/build/${PACKAGE_DEBFILE}" > /tmp/${PACKAGE_NAME}_sha256.hash
if [ "$(sha256sum -c /tmp/${PACKAGE_NAME}_sha256.hash | grep FAILED)" != "" ]; then
    echo "FATAL: Checksum did not match expected for $PACKAGE_NAME"
    exit 4
fi

# Wait until the package repository is not in use
while true; do
    apt-get check >/dev/null 2>&1
    if [ "$?" -eq "0" ]; then break; fi
    echo "Waiting for another installation process to finish..."
    sleep 1
done

# Install and cleanup
echo "Installing deb file: /opt/build/${PACKAGE_DEBFILE}"
gdebi --non-interactive /opt/build/${PACKAGE_DEBFILE}
rm /opt/build/${PACKAGE_DEBFILE}
