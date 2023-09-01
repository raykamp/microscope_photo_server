#!/bin/bash

set -e
trap 'echo -e "\033[0;31mError: Command on line $LINENO failed.\033[0m"' ERR

# Source the configuration file
source config.cfg

# Parameters
REPO_URL="https://github.com/raykamp/microscope_photo_server.git"
VENDOR_ID="04a9"
PRODUCT_ID="3218"

# Automatically detect the username
USERNAME=$(whoami)

# Check if directory exists, backup photos and remove it
if [ -d "$REPO_DIR" ]; then
    if [ -d "$REPO_DIR/$PHOTOS_DIR" ]; then
        echo "Backing up existing photos..."
        TMP_BACKUP_DIR=$(mktemp -d)
        cp -r "$REPO_DIR/$PHOTOS_DIR"/* "$TMP_BACKUP_DIR/"
    fi
    
    echo "Removing existing directory..."
    sudo rm -rf $REPO_DIR
fi

# Clone the repository to a safe location
echo "Cloning repository..."
sudo git clone $REPO_URL $REPO_DIR  || exit_with_error

# If there were photos in the old directory, migrate them to the new one
if [ -d "$TMP_BACKUP_DIR" ]; then
    echo "Restoring photos to new installation..."
    mkdir -p "$REPO_DIR/$PHOTOS_DIR"
    cp -r "$TMP_BACKUP_DIR/"* "$REPO_DIR/$PHOTOS_DIR/"
    rm -rf "$TMP_BACKUP_DIR"
fi

# Set the udev rule and permissions
echo "Setting udev rules..."
echo "ATTR{idVendor}==\"$VENDOR_ID\", ATTR{idProduct}==\"$PRODUCT_ID\", MODE=\"0660\", GROUP=\"plugdev\"" | sudo tee /etc/udev/rules.d/40-camera.rules
sudo usermod -aG plugdev $USERNAME
sudo udevadm control --reload-rules
sudo udevadm trigger

# Install and configure the Samba server
echo "Installing and setting up Samba..."
sudo apt-get update
sudo apt-get install samba -y
echo "[$SHARE_NAME]
   path = $REPO_DIR/$PHOTOS_DIR
   read only = no
   guest ok = yes" | sudo tee -a /etc/samba/smb.conf
sudo systemctl restart smbd

# Create a systemd service to run the script on startup
echo "Setting up the script to run on startup..."
SERVICE_CONTENT="[Unit]
Description=Microscope Photo Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 $REPO_DIR/script.py
Restart=always
User=$USERNAME
WorkingDirectory=$REPO_DIR
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target"

echo "$SERVICE_CONTENT" | sudo tee /etc/systemd/system/microscope-photo-server.service

sudo systemctl daemon-reload
sudo systemctl enable microscope-photo-server
sudo systemctl start microscope-photo-server

echo "Installation complete!"
