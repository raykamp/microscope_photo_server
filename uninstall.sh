#!/bin/bash

set -e
trap 'echo -e "\033[0;31mError: Command on line $LINENO failed.\033[0m"' ERR

# Source the configuration file
source config.cfg

# Automatically detect the username
USERNAME=$(whoami)

# Check if the service is active and running
if sudo systemctl is-active --quiet microscope-photo-server; then
    # Stop and disable the service
    sudo systemctl stop microscope-photo-server
    sudo systemctl disable microscope-photo-server
fi

# Check if the service file exists
if [ -e "/etc/systemd/system/microscope-photo-server.service" ]; then
    # Remove the systemd service file
    sudo rm /etc/systemd/system/microscope-photo-server.service

    # Reload systemd units
    sudo systemctl daemon-reload

    echo "Service uninstalled."
else
    echo "Service file not found. No action taken."
fi

# Remove the Samba configuration
sudo sed -i "/\[$SHARE_NAME\]/,/^$/d" /etc/samba/smb.conf
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
