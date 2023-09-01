#!/usr/bin/env python3

# TODO: Install script
# TODO: Install udev rule for permission to access camera as non-admin (04a9:3218)

import gphoto2 as gp
import os
import sys

def download_and_delete_file(camera, path, target_directory):
    folder, name = os.path.split(path)
    print(f"Downloading {path} to {target_directory}")
    
    camera_file = camera.file_get(folder, name, gp.GP_FILE_TYPE_NORMAL)
    camera_file.save(os.path.join(target_directory, name))
    
    # Delete file after download
    print(f"Deleting {name} from camera...")
    camera.file_delete(folder, name)

def tether_and_monitor_photos(target_directory):
    # Ensure the directory exists
    if not os.path.exists(target_directory):
        print(f"Directory '{target_directory}' does not exist. Please provide a valid directory.")
        sys.exit(1)

    # Create the camera object
    camera = gp.Camera()
    camera.init()

    print("Monitoring for new photos... (Press Ctrl+C to stop)")

    while True:
        # Use timeout for 3000ms or 3s. Adjust as needed.
        event_type, event_data = camera.wait_for_event(3000)
        if event_type == gp.GP_EVENT_FILE_ADDED:
            download_and_delete_file(camera, event_data.folder + event_data.name, target_directory)

    camera.exit()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 tether_script.py [target_directory]")
        sys.exit(1)

    target_directory = sys.argv[1]
    tether_and_monitor_photos(target_directory)
