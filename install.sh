#!/bin/bash

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "Script requires root privileges. Escalating..."
  sudo "$0" "$@"
  exit $?
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
        sudo chmod 775 "$INSTALL_DIR/$PHOTOS_DIR"
        
        # Restore the photos
        sudo cp -r "$TMP_BACKUP_DIR/"* "$INSTALL_DIR/$PHOTOS_DIR/"
        rm -rf "$TMP_BACKUP_DIR"
    fi
    
    exit 1
}

# Set trap to handle errors
trap handle_error ERR

# Source the configuration file
source config.cfg

# Check if directory exists, backup photos and remove it
if [ -d "$INSTALL_DIR" ]; then
    if [ -d "$INSTALL_DIR/$PHOTOS_DIR" ]; then
        shopt -s nullglob
        photo_files=("$INSTALL_DIR/$PHOTOS_DIR"/*)
        shopt -u nullglob
        
        if [ ${#photo_files[@]} -gt 0 ]; then
            echo "Backing up existing photos..."
            TMP_BACKUP_DIR=$(mktemp -d)
            for file in "${photo_files[@]}"; do
                cp "$file" "$TMP_BACKUP_DIR/"
            done
        fi
    fi
    
    # Prompt for confirmation
    read -p "This will uninstall the Microscope Photo Server and delete all associated data. Are you sure you want to proceed? (Y/N): " choice
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
sudo chmod 775 "$INSTALL_DIR/$PHOTOS_DIR"

# Copy files to installation path
echo "Copying files to installation path..."
cp -r ./* "$INSTALL_DIR/"

# Update permissions
chown -R $USERNAME:$USERNAME $INSTALL_DIR

# If there were photos in the old directory, migrate them to the new one
if [ -d "$TMP_BACKUP_DIR" ]; then
    echo "Restoring photos to new installation..."
    mkdir -p "$INSTALL_DIR/$PHOTOS_DIR"
    cp -r "$TMP_BACKUP_DIR/"* "$INSTALL_DIR/$PHOTOS_DIR/"
    rm -rf "$TMP_BACKUP_DIR"
fi

# Set the udev rule and permissions
echo "Setting udev rules..."
echo "ATTR{idVendor}==\"$VENDOR_ID\", ATTR{idProduct}==\"$PRODUCT_ID\", MODE=\"0660\", GROUP=\"plugdev\"" | sudo tee /etc/udev/rules.d/40-camera.rules
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
echo "[$SHARE_NAME]
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
RestartSec=5min
User=$USERNAME
WorkingDirectory=$INSTALL_DIR
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target"

echo "$SERVICE_CONTENT" | sudo tee /etc/systemd/system/microscope-photo-server.service

sudo systemctl daemon-reload
sudo systemctl enable microscope-photo-server
sudo systemctl start microscope-photo-server

echo "Installation complete!"
