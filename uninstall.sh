#!/bin/bash

# Automatically detect the username
if [ -n "$SUDO_USER" ]; then
    USERNAME="$SUDO_USER"
else
    USERNAME=$(whoami)
fi

set -e
trap 'echo -e "\033[0;31mError: Command on line $LINENO failed.\033[0m"' ERR

# Source the config parser module
source config_parser.sh

# Check if the service is active and running
if sudo systemctl is-active --quiet $SYSTEMD_SERVICE_NAME; then
    # Stop and disable the service
    sudo systemctl stop $SYSTEMD_SERVICE_NAME
    sudo systemctl disable $SYSTEMD_SERVICE_NAME
fi

# Check if the service file exists
if [ -e "/etc/systemd/system/$SYSTEMD_SERVICE_NAME.service" ]; then
    # Remove the systemd service file
    sudo rm /etc/systemd/system/$SYSTEMD_SERVICE_NAME.service

    # Reload systemd units
    sudo systemctl daemon-reload

    echo "Service uninstalled."
else
    echo "Service file not found. No action taken."
fi

# Remove the Samba configuration
sudo sed -i "/\[$SERVER_SHARE_NAME\]/,/^$/d" /etc/samba/smb.conf
sudo systemctl restart smbd

# Remove the udev rule if it exists
if [ -e "/etc/udev/rules.d/40-camera.rules" ]; then
    sudo rm /etc/udev/rules.d/40-camera.rules
fi

# Revert user to original group and home directory if the username is not "root"
if [ "$USERNAME" != "root" ]; then
    sudo usermod -G $USERNAME -d /home/$USERNAME $USERNAME
fi

# Remove installed files if the directory exists
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf $INSTALL_DIR
fi

echo "Uninstallation complete!"
