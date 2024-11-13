#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
MODDIR=${0%/*}

# Wait for boot to complete
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done
sleep 5

# Path to configuration file
CONFIG_FILE="/sdcard/Download/magisk-furtif.json"

# Load configuration values from JSON
DEVICE_NAME=$(jq -r '.device_name' "$CONFIG_FILE")
CHECK_INTERVAL=$(jq -r '.check_interval' "$CONFIG_FILE")
NETWORK_CHECK_INTERVAL=$(jq -r '.network_check_interval' "$CONFIG_FILE")
MIN_FREE_MEMORY_PERCENT=$(jq -r '.min_free_memory_percent' "$CONFIG_FILE")
DISCORD_WEBHOOK_URL=$(jq -r '.discord_webhook_url' "$CONFIG_FILE")

# Load tap and swipe coordinates and sleep durations
TAP1_X=$(jq -r '.start_coordinates.tap1.x' "$CONFIG_FILE")
TAP1_Y=$(jq -r '.start_coordinates.tap1.y' "$CONFIG_FILE")
TAP1_SLEEP=$(jq -r '.start_coordinates.tap1.sleep' "$CONFIG_FILE")

SWIPE_X1=$(jq -r '.start_coordinates.swipe.x1' "$CONFIG_FILE")
SWIPE_Y1=$(jq -r '.start_coordinates.swipe.y1' "$CONFIG_FILE")
SWIPE_X2=$(jq -r '.start_coordinates.swipe.x2' "$CONFIG_FILE")
SWIPE_Y2=$(jq -r '.start_coordinates.swipe.y2' "$CONFIG_FILE")
SWIPE_DURATION=$(jq -r '.start_coordinates.swipe.duration' "$CONFIG_FILE")
SWIPE_SLEEP=$(jq -r '.start_coordinates.swipe.sleep' "$CONFIG_FILE")

TAP2_X=$(jq -r '.start_coordinates.tap2.x' "$CONFIG_FILE")
TAP2_Y=$(jq -r '.start_coordinates.tap2.y' "$CONFIG_FILE")
TAP2_SLEEP=$(jq -r '.start_coordinates.tap2.sleep' "$CONFIG_FILE")

TAP3_X=$(jq -r '.start_coordinates.tap3.x' "$CONFIG_FILE")
TAP3_Y=$(jq -r '.start_coordinates.tap3.y' "$CONFIG_FILE")
TAP3_SLEEP=$(jq -r '.start_coordinates.tap3.sleep' "$CONFIG_FILE")

TAP4_X=$(jq -r '.start_coordinates.tap4.x' "$CONFIG_FILE")
TAP4_Y=$(jq -r '.start_coordinates.tap4.y' "$CONFIG_FILE")
TAP4_SLEEP=$(jq -r '.start_coordinates.tap4.sleep' "$CONFIG_FILE")

# add common packages to denylist
magisk --sqlite "REPLACE INTO denylist (package_name,process) VALUES('com.android.vending','com.android.vending');"
magisk --sqlite "DELETE FROM denylist (package_name='com.google.android.gms');"
magisk --sqlite "DELETE FROM denylist (package_name='com.google.android.gms.setup');"
#magisk --sqlite "REPLACE INTO denylist (package_name,process) VALUES('com.google.android.gsf','com.google.android.gsf');"
magisk --sqlite "REPLACE INTO denylist (package_name,process) VALUES('com.nianticlabs.pokemongo','com.nianticlabs.pokemongo');"
  
# Function to send a message to Discord
send_discord_message() {
    message=$1
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        curl -k -X POST "$DISCORD_WEBHOOK_URL" -H "Accept: application/json" -H "Content-Type: application/json" --data-binary @- <<DATA
        {
            "content": "${message}"
        }
DATA
    else
        echo "No internet connection for Discord message."
    fi
}

# Check if Pokémon GO and FurtifForMaps are running
check_device_status() {
    PidPOGO=$(pidof com.nianticlabs.pokemongo)
    PidAPK=$(pidof com.github.furtif.furtifformaps)
    if [[ -z "$PidPOGO" || -z "$PidAPK" ]]; then
        return 1
    fi
    return 0
}

# Check available memory and compare to minimum threshold
check_memory_status() {
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    free_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    free_mem_percent=$((100 * free_mem / total_mem))
    
    if [ "$free_mem_percent" -lt "$MIN_FREE_MEMORY_PERCENT" ]; then
        send_discord_message "⚠️ $DEVICE_NAME: Less than 10% memory available. Restarting apps."
        return 1
    fi
    return 0
}

# Check if network connection is available
check_network_connection() {
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        return 0  # Network available
    else
        return 1  # No network
    fi
}

# Close apps function
close_apps() {
    am force-stop com.github.furtif.furtifformaps
    am force-stop com.nianticlabs.pokemongo
    send_discord_message "🔴 $DEVICE_NAME: FurtifForMaps and Pokémon GO were closed."
    sleep 5
}

# Start FurtifForMaps and perform input actions
start_apk_tools() {
    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    sleep "$TAP1_SLEEP"
    input tap "$TAP1_X" "$TAP1_Y"
    sleep "$SWIPE_SLEEP"
    input swipe "$SWIPE_X1" "$SWIPE_Y1" "$SWIPE_X2" "$SWIPE_Y2" "$SWIPE_DURATION"
    sleep "$TAP2_SLEEP"
    input tap "$TAP2_X" "$TAP2_Y"
    sleep "$TAP3_SLEEP"
    input tap "$TAP3_X" "$TAP3_Y"
    sleep "$TAP4_SLEEP"
    input tap "$TAP4_X" "$TAP4_Y"
    send_discord_message "🟢 $DEVICE_NAME: FurtifForMaps started and actions performed."
}

# Initial start of APK tools
sleep 10
start_apk_tools
sleep "$CHECK_INTERVAL"

# Main loop to check network, memory, and app status
while true; do
    # Check network connection
    if ! check_network_connection; then
        send_discord_message "🔴 $DEVICE_NAME: No internet connection. Closing apps."
        close_apps
        
        # Wait for network to be restored
        while ! check_network_connection; do
            echo "Waiting for internet connection to be restored..."
            sleep "$NETWORK_CHECK_INTERVAL"
        done
        
        send_discord_message "🟢 $DEVICE_NAME: Internet connection restored. Restarting apps."
        start_apk_tools
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Check if apps are running
    if ! check_device_status; then
        send_discord_message "🔴 $DEVICE_NAME: Apps are offline. Restarting."
        close_apps
        start_apk_tools
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    # Check memory status
    if ! check_memory_status; then
        close_apps
        start_apk_tools
        sleep "$CHECK_INTERVAL"
        continue
    fi

    sleep "$CHECK_INTERVAL"
done
