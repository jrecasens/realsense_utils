#!/bin/bash


# Instructions (do not remove)
# chmod +x 2_librealsense.sh
# ./2_librealsense.sh

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

# Remove existing librealsense installation directories
echo "Removing existing librealsense directories..."
sudo rm -rf /home/tolveet/librealsense /usr/src/librealsense* /opt/librealsense /usr/local/lib/librealsense* /usr/local/lib64/librealsense* /usr/local/include/librealsense* /usr/local/bin/rs-* /etc/udev/rules.d/99-realsense-libusb.rules /etc/udev/rules.d/99-realsense-d4xx-mipi-dfu.rules 

# Remove all RealSense SDK-related packages
echo "Removing all RealSense SDK-related packages..."
PACKAGES=$(dpkg -l | grep "realsense" | awk '{print $2}')
if [ -n "$PACKAGES" ]; then
    echo $PACKAGES | xargs sudo dpkg --purge || {
        echo "Error: Failed to remove RealSense SDK-related packages."
        exit 1
    }
else
    echo "No RealSense SDK-related packages found. Skipping..."
fi

# Optionally remove any residual configuration files
echo "Removing residual configuration files..."
sudo apt-get autoremove --purge -y

# Update shared library cache
echo "Updating shared library cache..."
sudo ldconfig

# Update and upgrade the system
echo "Updating and upgrading the system..."
sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y

# Install the necessary dependencies
echo "Installing necessary dependencies..."
sudo apt-get install -y git libssl-dev libusb-1.0-0-dev libudev-dev pkg-config libgtk-3-dev libglfw3-dev build-essential cmake wget

# Ensure udev is in the path
echo "Ensuring udev is in the path..."
sudo apt-get install -y systemd udev

# Fetch the latest release tag of librealsense from GitHub
echo "Fetching the latest librealsense version..."
LATEST_VERSION=$(curl --silent "https://api.github.com/repos/IntelRealSense/librealsense/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Download librealsense sources
echo "Downloading librealsense version ${LATEST_VERSION}..."
WORKDIR="/usr/src"
sudo mkdir -p ${WORKDIR}
cd ${WORKDIR}
sudo curl -L "https://github.com/IntelRealSense/librealsense/archive/refs/tags/${LATEST_VERSION}.tar.gz" -o librealsense.tar.gz || {
    echo "Error: Failed to download librealsense."
    exit 1
}
sudo tar -zxf librealsense.tar.gz || {
    echo "Error: Failed to extract librealsense."
    exit 1
}
sudo rm librealsense.tar.gz

# Remove existing symbolic link if it exists
if [ -L "/usr/src/librealsense" ]; then
    sudo rm /usr/src/librealsense
fi

# Create a new symbolic link
sudo ln -s ${WORKDIR}/librealsense-${LATEST_VERSION//v/} /usr/src/librealsense

# Copy udev rules
echo "Adding udev rules..."
sudo cp ${WORKDIR}/librealsense-${LATEST_VERSION//v/}/config/99-realsense-libusb.rules /etc/udev/rules.d/ || {
    echo "Error: Failed to copy 99-realsense-libusb.rules."
    exit 1
}
sudo cp ${WORKDIR}/librealsense-${LATEST_VERSION//v/}/config/99-realsense-d4xx-mipi-dfu.rules /etc/udev/rules.d/ || {
    echo "Error: Failed to copy 99-realsense-d4xx-mipi-dfu.rules."
    exit 1
}

# Check for any /dev/video* device and run udevadm for all found devices
if ls /dev/video* 1> /dev/null 2>&1; then
    echo "Reloading udev rules and triggering udevadm..."
    sudo udevadm control --reload-rules && sudo udevadm trigger
fi

# Build and install the librealsense library
echo "Building and installing librealsense..."
cd ${WORKDIR}/librealsense-${LATEST_VERSION//v/} || {
    echo "Error: Failed to enter librealsense directory."
    exit 1
}
sudo rm -rf build && sudo mkdir build && cd build
sudo cmake -DCMAKE_C_FLAGS_RELEASE="${CMAKE_C_FLAGS_RELEASE} -s" \
          -DCMAKE_CXX_FLAGS_RELEASE="${CMAKE_CXX_FLAGS_RELEASE} -s" \
          -DCMAKE_INSTALL_PREFIX=/opt/librealsense \
          -DBUILD_GRAPHICAL_EXAMPLES=ON \
          -DBUILD_PYTHON_BINDINGS:bool=true \
          -DPYTHON_EXECUTABLE=/usr/bin/python3 \
          -DFORCE_RSUSB_BACKEND=OFF \
          -DCMAKE_BUILD_TYPE=Release ../ || {
    echo "Error: cmake failed."
    exit 1
}
sudo make -j$(($(nproc)-1)) all
sudo make install

# Add librealsense binaries to PATH
echo "Adding librealsense to PATH..."
export PATH=/opt/librealsense/bin:$PATH
echo 'export PATH=/opt/librealsense/bin:$PATH' | sudo tee -a /home/tolveet/.bashrc

# Add librealsense libraries to LD_LIBRARY_PATH
echo "Adding librealsense to LD_LIBRARY_PATH..."
export LD_LIBRARY_PATH=/opt/librealsense/lib:/usr/local/lib:/usr/local/lib64:$LD_LIBRARY_PATH
echo 'export LD_LIBRARY_PATH=/opt/librealsense/lib:/usr/local/lib:/usr/local/lib64:$LD_LIBRARY_PATH' | sudo tee -a /home/tolveet/.bashrc

source /home/tolveet/.bashrc

# Reload the videodev module
echo "Reloading videodev module..."
sudo modprobe videodev

# Final message
echo "librealsense version ${LATEST_VERSION} installed successfully in /opt/librealsense."

# Prompt the user for a system restart
echo "A system restart may be necessary to ensure that all changes take effect properly."
read -p "Would you like to restart your system now? (y/n): " RESTART_CHOICE

if [[ "$RESTART_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Restarting system..."
    sudo reboot
else
    echo "Please consider restarting your system manually later to ensure all changes are applied."
fi

