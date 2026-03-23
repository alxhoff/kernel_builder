#!/bin/bash

# A script to stream multiple RealSense depth cameras from a Jetson
# and receive them on a host machine.

# --- Configuration ---
# IP address of the machine that will receive the video (your host PC)
RECEIVER_IP="192.168.1.71"
# Base UDP port for the streams. Each camera will use a different port, starting from this one.
BASE_PORT=5000
# The script will look for cameras from video-rs-depth-0 up to this number.
NUM_CAMERAS=4

# --- Function to kill all child processes of this script ---
cleanup() {
    echo -e "\nCleaning up background processes..."
    # The '-P $$' flag targets all child processes of the current script's PID.
    pkill -P $$
}

# Trap the exit signal to run the cleanup function, ensuring background streams are stopped.
trap cleanup EXIT

# --- Sender Logic (to be run on the Jetson) ---
run_sender() {
    echo "Starting sender..."
    # Loop from 0 to (NUM_CAMERAS - 1)
    for i in $(seq 0 $((NUM_CAMERAS - 1))); do
        DEVICE_SYM_PATH="/dev/video-rs-ir-$i"

        # Check if the symbolic link for the camera exists
        if [ -L "$DEVICE_SYM_PATH" ]; then
            DEVICE_PATH=$(readlink -f "$DEVICE_SYM_PATH")
            PORT=$((BASE_PORT + i))
            echo "Streaming $DEVICE_PATH to $RECEIVER_IP:$PORT"

            # This pipeline uses software encoding because your Jetson is missing the
            # NVIDIA GStreamer plugins.
            # NOTE: Depth cameras have different formats. 'video/x-raw,format=GRAY8'
            # is a common one, but you may need to adjust width, height, format,
            # and framerate if this does not work.
            sudo gst-launch-1.0 v4l2src device="$DEVICE_PATH" ! \
                'video/x-raw,width=848,height=480,framerate=15/1' ! \
                videoconvert ! \
                x264enc tune=zerolatency ! \
                rtph264pay ! \
                udpsink host="$RECEIVER_IP" port="$PORT" &
        else
            echo "Warning: Camera device $DEVICE_SYM_PATH not found. Skipping."
        fi
    done

    echo "Sender pipelines started. Press Ctrl+C in this terminal to stop all streams."
    # 'wait' will pause the script here, allowing the background jobs to run.
    # It will be interrupted by Ctrl+C, which then triggers the 'cleanup' trap.
    wait
}

# --- Receiver Logic (to be run on the Host PC) ---
run_receiver() {
    echo "Starting receiver..."
    for i in $(seq 0 $((NUM_CAMERAS - 1))); do
        PORT=$((BASE_PORT + i))
        echo "Opening window for stream on port $PORT"

        # This pipeline receives a stream and displays it in a new window.
        gst-launch-1.0 udpsrc port="$PORT" ! \
            "application/x-rtp,media=video,encoding-name=H264,payload=96" ! \
            rtph264depay ! \
            avdec_h264 ! \
            videoconvert ! \
            autovideosink &
    done

    echo "Receiver windows starting. Press Ctrl+C in this terminal to close all."
    wait
}

# --- Main Script Logic ---
# Check the first command-line argument.
if [ "$1" == "sender" ]; then
    run_sender
elif [ "$1" == "receiver" ]; then
    run_receiver
else
    echo "Usage: $0 <sender|receiver>"
    echo "  - Run with 'sender' on the Jetson to start streaming."
    echo "  - Run with 'receiver' on your host PC to view the streams."
    exit 1
fi
