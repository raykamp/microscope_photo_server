#!/usr/bin/env python3

import gphoto2 as gp
import os
import sys
import datetime
import uuid

MEDIA_DIR_ON_CAEMRA = "/DCIM/100CANON"
MEDIA_FILETYPES_SUPPORTED = ['.jpg', '.jpeg', '.png', '.raw', '.tif', '.mp4', '.mov', '.avi', '.mkv']


def download_and_delete_file(camera, path, target_directory):
    folder, name = os.path.split(path)
    
    # Create unique filename using current date-time and a random string
    file_extension = os.path.splitext(name)[1]  # get the file extension (e.g., .jpg)
    unique_name = datetime.datetime.now().strftime("photo_%Y-%m-%d_%H-%M-%S_") + str(uuid.uuid4().hex)[:6] + file_extension
    
    output_path = os.path.join(target_directory, unique_name)
    print(f"Downloading {path} to {target_directory}")
    
    camera_file = camera.file_get(folder, name, gp.GP_FILE_TYPE_NORMAL)
    camera_file.save(output_path)
    os.chmod(output_path, 0o666)
    
    # Delete file after download
    print(f"Deleting {name} from camera...")
    camera.file_delete(folder, name)

def download_all_existing_files(camera, target_directory):
    # Define folder where photos are stored
    photo_folder = MEDIA_DIR_ON_CAEMRA
    # File extensions considered as photos
    photo_extensions = [ext.lower() for ext in MEDIA_FILETYPES_SUPPORTED] 

    # Fetch and download all photo files from the specified folder
    for file in camera.folder_list_files(photo_folder):
        _, ext = os.path.splitext(file)
        if ext.lower() in photo_extensions:
            download_and_delete_file(camera, os.path.join(photo_folder, file), target_directory)



def tether_and_monitor_photos(target_directory):
   # Create the directory if it doesn't exist
    if not os.path.exists(target_directory):
        os.makedirs(target_directory)

    # Create the camera object
    camera = gp.Camera()
    camera.init()

    # Download all existing files upon first connection
    download_all_existing_files(camera, target_directory)

    print("Monitoring for new photos and videos... (Press Ctrl+C to stop)")

    try:
        while True:
            # Use timeout for 3000ms or 3s. Adjust as needed.
            event_type, event_data = camera.wait_for_event(3000)
            if event_type == gp.GP_EVENT_FILE_ADDED:
                download_and_delete_file(camera, event_data.folder + event_data.name, target_directory)
                # Double-check for any remaining media files
                download_all_existing_files(camera, target_directory)
    except KeyboardInterrupt:
        pass

    camera.exit()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 tether_script.py [target_directory]")
        sys.exit(1)

    target_directory = sys.argv[1]
    tether_and_monitor_photos(target_directory)
