#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
#!/system/bin/sh
MODDIR=${0%/*}

# Wait for the boot process to complete
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done
sleep 5

# configuration files
DEVICE_CONFIG_FILE="/data/data/com.github.furtif.furtifformaps/files/config.json"
SCRIPT_CONFIG_FILE="/sdcard/Download/config.json"

# Read the device and Rotom configuration
DEVICE_NAME=$(jq -r '.RotomDeviceName' "$DEVICE_CONFIG_FILE")
ROTOM_URL=$(jq -r '.RotomURL' "$DEVICE_CONFIG_FILE")

# Read the script configuration
DISCORD_WEBHOOK_URL=$(jq -r '.discordWebhookUrl' "$SCRIPT_CONFIG_FILE")
CHECK_INTERVAL=$(jq -r '.checkInterval' "$SCRIPT_CONFIG_FILE")

# Variables for start_apk_tools
TAP1_X=$(jq -r '.startApkTools.tap1.x' "$SCRIPT_CONFIG_FILE")
TAP1_Y=$(jq -r '.startApkTools.tap1.y' "$SCRIPT_CONFIG_FILE")
TAP1_SLEEP=$(jq -r '.startApkTools.tap1.sleep' "$SCRIPT_CONFIG_FILE")

SWIPE_START_X=$(jq -r '.startApkTools.swipe.startX' "$SCRIPT_CONFIG_FILE")
SWIPE_START_Y=$(jq -r '.startApkTools.swipe.startY' "$SCRIPT_CONFIG_FILE")
SWIPE_END_X=$(jq -r '.startApkTools.swipe.endX' "$SCRIPT_CONFIG_FILE")
SWIPE_END_Y=$(jq -r '.startApkTools.swipe.endY' "$SCRIPT_CONFIG_FILE")
SWIPE_DURATION=$(jq -r '.startApkTools.swipe.duration' "$SCRIPT_CONFIG_FILE")
SWIPE_SLEEP=$(jq -r '.startApkTools.swipe.sleep' "$SCRIPT_CONFIG_FILE")

TAP2_X=$(jq -r '.startApkTools.tap2.x' "$SCRIPT_CONFIG_FILE")
TAP2_Y=$(jq -r '.startApkTools.tap2.y' "$SCRIPT_CONFIG_FILE")
TAP2_SLEEP=$(jq -r '.startApkTools.tap2.sleep' "$SCRIPT_CONFIG_FILE")

TAP3_X=$(jq -r '.startApkTools.tap3.x' "$SCRIPT_CONFIG_FILE")
TAP3_Y=$(jq -r '.startApkTools.tap3.y' "$SCRIPT_CONFIG_FILE")
TAP3_SLEEP=$(jq -r '.startApkTools.tap3.sleep' "$SCRIPT_CONFIG_FILE")

TAP4_X=$(jq -r '.startApkTools.tap4.x' "$SCRIPT_CONFIG_FILE")
TAP4_Y=$(jq -r '.startApkTools.tap4.y' "$SCRIPT_CONFIG_FILE")
TAP4_SLEEP=$(jq -r '.startApkTools.tap4.sleep' "$SCRIPT_CONFIG_FILE")

# Function to send a message to Discord
send_discord_message() {
    message=$1
    curl -k -X POST "$DISCORD_WEBHOOK_URL" -H "Accept: application/json" -H "Content-Type: application/json" --data-binary @- <<DATA
    {
        "content": "${message}"
    }
DATA
}

# Event logging function
log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /sdcard/Download/device_monitor.log
}

# Function to check the device status via the API
check_device_status() {
    response=$(curl -s "$ROTOM_URL/api/status")

    if [ -z "$response" ]; then
        send_discord_message "⚠️ Warning: Could not retrieve status from API. Check network connectivity."
        log_event "Error: Failed to retrieve status from API."
        return
    fi
    
    # Extract device information based on the stored device name
    device_info=$(echo "$response" | jq -r --arg name "$DEVICE_NAME" '.devices[] | select(.origin | contains($name))')
    
    if [ -z "$device_info" ]; then
        send_discord_message "⚠️ Warning: Device $DEVICE_NAME not found in API response."
        log_event "Error: Device $DEVICE_NAME not found in API response."
        return
    fi

    is_alive=$(echo "$device_info" | jq -r '.isAlive')
    mem_free=$(echo "$device_info" | jq -r '.lastMemory.memFree')
    
    if [ "$is_alive" = "false" ] || [ "$mem_free" -lt 200000 ]; then
        send_discord_message "🔴 Alert: Device $DEVICE_NAME is offline or low on memory. Rebooting now..."
        log_event "Rebooting due to offline status or low memory."
        reboot
    else
        log_event "Device $DEVICE_NAME status OK: Online with sufficient memory."
    fi
}

# Starts the APK and performs the necessary interactions
start_apk_tools() {
    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    sleep 10
    input tap "$TAP1_X" "$TAP1_Y"
    sleep "$TAP1_SLEEP"
    input swipe "$SWIPE_START_X" "$SWIPE_START_Y" "$SWIPE_END_X" "$SWIPE_END_Y" "$SWIPE_DURATION"
    sleep "$SWIPE_SLEEP"
    input tap "$TAP2_X" "$TAP2_Y"
    sleep "$TAP2_SLEEP"
    input tap "$TAP3_X" "$TAP3_Y"
    sleep "$TAP3_SLEEP"
    input tap "$TAP4_X" "$TAP4_Y"
    sleep "$TAP4_SLEEP"
    send_discord_message "🟢 $DEVICE_NAME: FurtifForMaps started and actions performed."
    log_event "FurtifForMaps started and actions performed."
}

# main execution
sleep 10  # Additional start delay

# Start the APK when the script starts
start_apk_tools

# Waiting time before starting the status check loop
sleep "$CHECK_INTERVAL"

# main loop for regular checking
while true; do
    check_device_status
    sleep "$CHECK_INTERVAL"
done
