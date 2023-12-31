#!/bin/bash

# Source the config parser module
source config_parser.sh

PHOTO_DIR_PERMISSIONS=777

# Automatically detect the username
if [ -n "$SUDO_USER" ]; then
    USERNAME="$SUDO_USER"
else
    USERNAME=$(whoami)
fi

# Check if script is not running as root
if [ "$EUID" -ne 0 ]; then
    # Prompt the user for confirmation
    read -p "This script needs to run with root privileges. Do you want to continue? (y/n) " choice
    choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')  # Convert the input to uppercase

    # Check if the choice is "Y"
    if [ "$choice" != "Y" ]; then
        echo "Exiting script."
        exit 1
    fi

    # Re-run the script with sudo
    exec sudo "$0" "$@"
fi

# rest of your script starts here
echo "Running with root privileges."

# Function to be called in case of error
handle_error() {
    echo -e "\033[0;31mError: Command on line $LINENO failed.\033[0m"
    
    # If there were photos in the temporary backup directory, recreate the install directory and restore them
    if [ -d "$TMP_BACKUP_DIR" ]; then
        echo "Error encountered. Restoring photos for potential re-attempt..."
        
        # Create the target directory
        sudo mkdir -p $INSTALL_DIR
        
        # Create the photos directory
        sudo mkdir -p "$INSTALL_DIR/$PHOTOS_DIR"
        sudo chmod "$PHOTO_DIR_PERMISSIONS" "$INSTALL_DIR/$PHOTOS_DIR"
        
        # Restore the photos
        sudo cp -r "$TMP_BACKUP_DIR/"* "$INSTALL_DIR/$PHOTOS_DIR/"
        rm -rf "$TMP_BACKUP_DIR"
    fi
    
    exit 1
}

# Set trap to handle errors
trap handle_error ERR

# Check if directory exists, backup photos and remove it
if [ -d "$INSTALL_DIR" ]; then
    if [ -d "$INSTALL_DIR/$PHOTOS_DIR" ]; then
        shopt -s nullglob
        photo_files=("$INSTALL_DIR/$PHOTOS_DIR"/*)
        shopt -u nullglob
        
        if [ ${#photo_files[@]} -gt 0 ]; then
            echo "A previous installation has been detected."
            echo "Backing up existing photos..."
            TMP_BACKUP_DIR=$(mktemp -d)
            for file in "${photo_files[@]}"; do
                cp "$file" "$TMP_BACKUP_DIR/"
            done
        fi
    fi
    
    # Prompt for confirmation
    read -p "The previous installation will be uninstalled and all associated data deleted. Are you sure you want to proceed? (Y/N): " choice
    # Convert choice to uppercase
    choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')

    if [ "$choice" == "Y" ]; then
        # Uninstall previous installation
        echo "Uninstalling previous installation..."
        sudo ./uninstall.sh
        echo "Previous installation has been uninstalled."
    fi
fi

# Create the target directory if it doesn't exist
sudo mkdir -p $INSTALL_DIR
# Create the photos directory if it doesn't exist
sudo mkdir -p "$INSTALL_DIR/$PHOTOS_DIR"
# Grant RW permissions for all users on the photos directory
sudo chmod "$PHOTO_DIR_PERMISSIONS" "$INSTALL_DIR/$PHOTOS_DIR"

# Copy files to installation path
echo "Copying files to installation path..."
cp -r ./* "$INSTALL_DIR/"

# If there were photos in the old directory, migrate them to the new one
if [ -d "$TMP_BACKUP_DIR" ]; then
    echo "Restoring photos to new installation..."
    mkdir -p "$INSTALL_DIR/$PHOTOS_DIR"
    cp -r "$TMP_BACKUP_DIR/"* "$INSTALL_DIR/$PHOTOS_DIR/"
    rm -rf "$TMP_BACKUP_DIR"
fi

# Update permissions
chown -R $USERNAME:$USERNAME $INSTALL_DIR

# Set the udev rule and permissions
echo "Setting udev rules..."
echo "ATTR{idVendor}==\"$CAMERACONFIG_VENDOR_ID\", ATTR{idProduct}==\"$CAMERACONFIG_PRODUCT_ID\", MODE=\"0660\", GROUP=\"plugdev\"" | sudo tee /etc/udev/rules.d/40-camera.rules
sudo usermod -aG plugdev $USERNAME
sudo udevadm control --reload-rules
sudo udevadm trigger

# Install libgphoto2-6
sudo apt-get update
sudo apt-get install libgphoto2-6 -y

# Install gphoto2 python bindings using the --user flag
sudo -H pip install gphoto2

# Install and configure the Samba server
echo "Installing and setting up Samba..."
sudo apt-get update
sudo apt-get install samba -y
echo "[$SERVER_SHARE_NAME]
    path = $INSTALL_DIR/$PHOTOS_DIR
    read only = no
    create mask = 0755
    directory mask = 0755
    guest ok = yes
    writable = yes
    delete readonly = yes" | sudo tee -a /etc/samba/smb.conf
sudo systemctl restart smbd

# Create a systemd service to run the script on startup
echo "Setting up the script to run on startup..."
SERVICE_CONTENT="[Unit]
Description=Microscope Photo Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/script.py $INSTALL_DIR/$PHOTOS_DIR
Restart=always
RestartSec=1min
User=$USERNAME
WorkingDirectory=$INSTALL_DIR
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target"

echo "$SERVICE_CONTENT" | sudo tee /etc/systemd/system/$SYSTEMD_SERVICE_NAME.service

sudo systemctl daemon-reload
sudo systemctl enable $SYSTEMD_SERVICE_NAME
sudo systemctl start $SYSTEMD_SERVICE_NAME

echo "Installation complete!"
