#!/bin/bash

# ==============================================================================
# Multi-Camera RealSense Streamer
# ==============================================================================

# --- Defaults ---
RECEIVER_IP="192.168.1.71"
BASE_PORT=5000
NUM_CAMERAS=4

# --- Transmission Settings ---
# We capture at native resolution, but scale down for transmission
# to save bandwidth and CPU.
SEND_WIDTH=640
SEND_HEIGHT=512

# Initialize state variables
MODE=""
IS_RGB=false

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        sender|receiver)
            MODE="$key"
            shift
            ;;
        --ip)
            RECEIVER_IP="$2"
            shift
            shift
            ;;
        --rgb)
            IS_RGB=true
            shift
            ;;
        *)
            echo "Error: Unknown option '$1'"
            exit 1
            ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "Usage: $0 <sender|receiver> [--ip <IP>] [--rgb]"
    exit 1
fi

cleanup() {
    echo -e "\nCleaning up background processes..."
    pkill -P $$
}
trap cleanup EXIT

# --- Sender Logic (Jetson) ---
run_sender() {
    echo "----------------------------------------"
    echo "STARTING SENDER"
    echo "Target IP: $RECEIVER_IP"
    echo "Mode:      $( [ "$IS_RGB" = true ] && echo "RGB (Using UYVY)" || echo "Depth" )"
    echo "----------------------------------------"

    for i in $(seq 0 $((NUM_CAMERAS - 1))); do
        PORT=$((BASE_PORT + i))

        if [ "$IS_RGB" = true ]; then
            # RGB Mode (Actually IR/UYVY based on your logs)
            DEVICE_PATH="/dev/video$i"

            # 1. Matches your v4l2-ctl output exactly
            SRC_CAPS="video/x-raw,format=UYVY,width=1920,height=1536,framerate=30/1"

            # 2. Pipeline with Scaling
            # v4l2src: Grabs massive 1920x1536 image
            # videoconvert: Converts UYVY to format compatible with scaler
            # videoscale: Shrinks image to 640x512 to save WiFi bandwidth
            PIPELINE_START="v4l2src device=$DEVICE_PATH ! $SRC_CAPS ! videoconvert ! videoscale ! video/x-raw,width=$SEND_WIDTH,height=$SEND_HEIGHT"
        else
            # Depth Mode
            SYM_PATH="/dev/video-rs-ir-$i"
            if [ -L "$SYM_PATH" ]; then
                DEVICE_PATH=$(readlink -f "$SYM_PATH")
            else
                echo "Warning: Symlink $SYM_PATH not found."
                continue
            fi
            # Standard Depth config
            SRC_CAPS="video/x-raw,width=848,height=480,framerate=15/1"
            PIPELINE_START="v4l2src device=$DEVICE_PATH ! $SRC_CAPS ! videoconvert"
        fi

        if [ -e "$DEVICE_PATH" ]; then
            echo "[Cam $i] Streaming $DEVICE_PATH -> $RECEIVER_IP:$PORT"

            gst-launch-1.0 $PIPELINE_START ! \
                x264enc tune=zerolatency bitrate=1500 speed-preset=ultrafast ! \
                rtph264pay ! \
                udpsink host="$RECEIVER_IP" port="$PORT" sync=false async=false &
        else
            echo "Error: Device node $DEVICE_PATH does not exist."
        fi
    done

    echo "Sender pipelines started. Press Ctrl+C to stop."
    wait
}

# --- Receiver Logic (Host PC) ---
run_receiver() {
    echo "Starting Receiver..."
    for i in $(seq 0 $((NUM_CAMERAS - 1))); do
        PORT=$((BASE_PORT + i))
        echo "Opening window for stream on port $PORT"
        gst-launch-1.0 udpsrc port="$PORT" ! \
            "application/x-rtp,media=video,encoding-name=H264,payload=96" ! \
            rtph264depay ! \
            avdec_h264 ! \
            videoconvert ! \
            autovideosink sync=false &
    done
    wait
}

if [ "$MODE" == "sender" ]; then
    run_sender
elif [ "$MODE" == "receiver" ]; then
    run_receiver
fi
