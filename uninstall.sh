#!/bin/bash

# Source the configuration file
source config.cfg

# Parameters

# Stop and remove the systemd service
echo "Stopping the service..."
sudo systemctl stop microscope-photo-server
sudo systemctl disable microscope-photo-server
echo "Removing the service..."
sudo rm /etc/systemd/system/microscope-photo-server.service
sudo systemctl daemon-reload
sudo systemctl reset-failed

# Remove udev rule and permissions
echo "Removing udev rules..."
sudo rm /etc/udev/rules.d/40-camera.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Remove the Samba share configuration
echo "Removing Samba share..."
sudo sed -i "/\[$SHARE_NAME\]/,/^$/d" /etc/samba/smb.conf
sudo systemctl restart smbd

# Remove the cloned repository
echo "Removing repository directory..."
sudo rm -rf $REPO_DIR

echo "Uninstallation complete!"
