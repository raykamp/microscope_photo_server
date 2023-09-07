#!/usr/bin/env python3

#TODO: Figure out why captured photos that aren't yet 24 years old aren't remaining on the camera and able to be previewed?

import gphoto2 as gp
import os
import sys
import datetime
import uuid
import re
import time
import configparser
import pickle

DOWNLOADED_DATA_PERSISTENT_SET_FILE = 'downloaded_files.pkl'

# Create a config parser and read the config file
config = configparser.ConfigParser()
config.read('config.ini')

# A set to keep track of downloaded files
downloaded_files = set()

# Read parameters from the config file
MEDIA_DIRS_ON_CAMERA_REGEX = config.get('CameraConfig', 'MEDIA_DIRS_ON_CAMERA_REGEX').replace('"', '')
MEDIA_FILETYPES_SUPPORTED =  [filetype.strip() for filetype in config.get('CameraConfig', 'MEDIA_FILETYPES_SUPPORTED').replace('"', '').split(',')]

def file_hash(file_path):
    """Generate a hash for a file."""
    import hashlib
    with open(file_path, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()


def persist_downloaded_files():
    # Store the updated set to a persistent file for future runs
    with open(DOWNLOADED_DATA_PERSISTENT_SET_FILE, 'wb') as f:
        pickle.dump(downloaded_files, f)


def get_target_directories(camera, regex=MEDIA_DIRS_ON_CAMERA_REGEX):
    # Define the regular expression pattern for matching folders
    pattern = re.compile(regex, re.IGNORECASE)

    # Fetch and check folders in the base directory
    camera_dirs = get_all_directories_on_camera(camera)

    # Filter folders based on the pattern
    matching_dirs = [os.path.join("/", dir) for dir in camera_dirs if pattern.match(dir)]

    return matching_dirs


def download_file(camera, path, target_directory):
    dir, name = os.path.split(path)

    # Decide based on path 
    if path in downloaded_files:
        print(f"Skipping already downloaded file: {name}")
        return

    # Fetch the file info which contains the timestamp
    info = camera.file_get_info(dir, name)
    timestamp = info.file.mtime

    # Convert the timestamp to a datetime object
    dt = datetime.datetime.fromtimestamp(timestamp)

    # Create unique filename using the photo's date-time and a random string
    file_extension = os.path.splitext(name)[1]
    unique_name = dt.strftime("photo_%Y-%m-%d_%H-%M-%S_") + str(uuid.uuid4().hex)[:6] + file_extension

    output_path = os.path.join(target_directory, unique_name)
    print(f"Downloading {path} to {output_path}")

    camera_file = camera.file_get(dir, name, gp.GP_FILE_TYPE_NORMAL)
    camera_file.save(output_path)
    os.chmod(output_path, 0o666)

    # After successful download, add file path to the set
    downloaded_files.add(path)
    persist_downloaded_files()



def delete_file_from_camera(camera, path):
    dir, name = os.path.split(path)

    # Delete the file
    camera.file_delete(dir, name)

    # Remove the file name from the set
    downloaded_files.discard(path) 
    persist_downloaded_files()


def delete_old_files_from_camera(camera, time_duration=datetime.timedelta(days=1)):
    """
    Deletes files from the camera that are older than the specified time_duration.

    Args:
    - camera: The camera object.
    - time_duration: A datetime.timedelta object specifying the age after which files should be deleted.
    """
    now = datetime.datetime.now()
    
    # Filter folders based on the target pattern
    target_dirs = get_target_directories(camera)

    for dir in target_dirs:
        for file, _ in camera.folder_list_files(dir):
            info = camera.file_get_info(dir, file)
            file_time = datetime.datetime.fromtimestamp(info.file.mtime)
            
            # If file is older than the specified time_duration, delete it
            if (now - file_time) > time_duration:
                print(f"Deleting old file: {file}")
                delete_file_from_camera(camera, os.path.join(dir, file))



def get_all_directories_on_camera(camera, directory_path="/"):
    """Get all directories recursively from the specified path."""
    directories = []
    
    # List directories in the current directory_path
    directory_names = [name for name, _ in camera.folder_list_folders(directory_path)]

    for directory in directory_names:
        current_path = os.path.join(directory_path, directory)
        directories.append(current_path)

        # Recursively add sub-directories
        directories.extend(get_all_directories_on_camera(camera, current_path))
    
    return directories


def download_all_existing_files(camera, target_directory):
    # File extensions considered as photos
    photo_extensions = [ext.lower() for ext in MEDIA_FILETYPES_SUPPORTED] 

    # Filter folders based on the target pattern
    target_dirs = get_target_directories(camera)
    
    # For each matching folder, fetch and download files
    for dir in target_dirs:
        for file, _ in camera.folder_list_files(dir):
            _, ext = os.path.splitext(file)
            if ext.lower() in photo_extensions:
                download_file(camera, os.path.join(dir, file), target_directory)




def tether_and_monitor_photos(target_directory):
   # Create the directory if it doesn't exist
    if not os.path.exists(target_directory):
        os.makedirs(target_directory)

    print("Attempting to connect to camera...")

    while True:
        try:
            # Create the camera object
            camera = gp.Camera()
            camera.init()
            # get configuration tree
            camera_config = camera.get_config()
            # Configure the photo capture target to be the SD card
            capture_target = camera_config.get_child_by_name('capturetarget')
            value = capture_target.get_choice(1) # captures are saved to SD card
            capture_target.set_value(value) 
            # Configure video capture target to be the SD card
            movie_record_target = camera_config.get_child_by_name('movierecordtarget')
            value = movie_record_target.get_choice(0) # captures are saved to SD card
            movie_record_target.set_value(value) 
            # Set the configuration
            camera.set_config(camera_config)

            # Download all existing files upon first connection
            download_all_existing_files(camera, target_directory)
            delete_old_files_from_camera(camera)

            print("Monitoring for new photos and videos... (Press Ctrl+C to stop)")

            while True:
                # Use timeout for 3000ms or 3s. Adjust as needed.
                event_type, event_data = camera.wait_for_event(3000)
                if event_type == gp.GP_EVENT_FILE_ADDED:
                    download_file(camera, os.path.join(event_data.folder, event_data.name), target_directory)
                    # Delete old files
                    delete_old_files_from_camera(camera)
        except KeyboardInterrupt:
            print("\nExiting program...")
            camera.exit()
            break
        except gp.GPhoto2Error as ex:
            print(f"Error: {str(ex)}. Attempting to reconnect in 5 seconds...")
            try:
                camera.exit()
            except:
                pass
            time.sleep(5)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 tether_script.py [target_directory]")
        sys.exit(1)

    # Load previously downloaded files
    if os.path.exists(DOWNLOADED_DATA_PERSISTENT_SET_FILE):
        with open(DOWNLOADED_DATA_PERSISTENT_SET_FILE, 'rb') as f:
            downloaded_files = pickle.load(f)

    target_directory = sys.argv[1]
    tether_and_monitor_photos(target_directory)
