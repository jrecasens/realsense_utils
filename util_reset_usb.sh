#!/bin/bash

# Ensure the script is run with root privileges
if [ "$(id -u)" -ne "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Check for /dev/video* devices and unload the videodev module if necessary
if ls /dev/video* 1> /dev/null 2>&1; then
    echo "videodev module is in use. Stopping related processes..."
    
    # Kill processes using videodev
    PIDS=$(sudo lsof /dev/video* | awk 'NR>1 {print $2}' | sort -u)
    if [ -n "$PIDS" ]; then
        echo "Stopping processes using videodev: $PIDS"
        sudo kill -9 $PIDS
    fi
    
    # Stop specific kernel modules associated with the video devices
    echo "Unloading video-related kernel modules..."
    sudo modprobe -r uvcvideo || echo "uvcvideo module not loaded, skipping..."
    sudo modprobe -r ov13858 || echo "ov13858 module not loaded, skipping..."
    sudo modprobe -r videobuf2_v4l2 || echo "videobuf2_v4l2 module not loaded, skipping..."
    
    # Retry unloading videodev module
    echo "Unloading videodev module..."
    sudo modprobe -r videodev || {
        echo "Error: Could not unload videodev module."
        exit 1
    }
else
    echo "No /dev/video* devices found. Skipping videodev unloading."
fi

# Install dependencies
echo "Installing dependencies..."
apt-get update -y
apt-get install -y usbutils pciutils build-essential

# Function to reset PCI USB controllers by unbinding and binding them
reset_pci_usb_controllers() {
    echo "Resetting all PCI USB controllers..."
    for pci_id in $(lspci -nn | grep -i usb | awk '{print $1}'); do
        local unbind_path="/sys/bus/pci/drivers/xhci_hcd/unbind"
        local bind_path="/sys/bus/pci/drivers/xhci_hcd/bind"

        echo "Unbinding USB controller $pci_id"
        echo "0000:$pci_id" | sudo tee "$unbind_path" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to unbind USB controller $pci_id, skipping."
            continue
        fi

        sleep 2  # Short delay to ensure unbinding is processed

        echo "Binding USB controller $pci_id"
        echo "0000:$pci_id" | sudo tee "$bind_path" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to bind USB controller $pci_id."
        else
            echo "Successfully rebound USB controller $pci_id."
        fi
    done
}

# Reset PCI USB controllers by unbinding and binding
reset_pci_usb_controllers

# Sleep again to ensure everything is settled
echo "Sleeping for 5 seconds to ensure controllers are fully bound..."
sleep 5

# Reset all USB devices using udevadm trigger
reset_usb_devices_with_udevadm() {
    echo "Resetting all USB devices using udevadm trigger..."
    udevadm trigger --subsystem-match=usb --action=add
    if [ $? -ne 0 ]; then
        echo "Failed to reset USB devices using udevadm."
    else
        echo "Reset successful for all USB devices using udevadm."
    fi
}

# Reset all USB devices using udevadm
reset_usb_devices_with_udevadm

# List all USB devices after reset
echo "Listing all USB devices after reset..."
lsusb

echo "USB reset process completed."

