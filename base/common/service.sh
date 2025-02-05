#!/system/bin/sh
MODDIR=${0%/*}

while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done

MAX_WAIT=30
start_time=$(date +%s)
while true; do
    if ip route get 1.1.1.1 &> /dev/null && \
       ping -c1 1.1.1.1 &> /dev/null && \
       [ "$(getprop service.bootanim.exit)" = "1" ]; then
        break
    fi

    if [ $(($(date +%s) - start_time)) -ge $MAX_WAIT ]; then
        break
    fi
    sleep 2
done

while [ ! -d "/sdcard/Download" ]; do
    sleep 1
done

local_ip="$(ip route get 1.1.1.1 | awk '{print $7}')"

CONFIG_FILE="/sdcard/Download/config.json"
LOG_FILE="/sdcard/Download/device_monitor.log"

if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE" || {
        echo "Failed to delete existing log file. Exiting."
        exit 1
    }
fi

touch "$LOG_FILE" || {
    echo "Failed to create log file. Exiting."
    exit 1
}
chmod 0666 "$LOG_FILE" 2>/dev/null || true

get_info() {
pogo_version="$(dumpsys package com.nianticlabs.pokemongo | awk -F "=" '/versionName/ {print $2}')"
mitm_version="$(dumpsys package com.github.furtif.furtifformaps | awk -F "=" '/versionName/ {print $2}')"
temperature="$(cat /sys/class/thermal/thermal_zone0/temp | awk '{print substr($0, 1, length($0)-3)}')"
module_version=$(awk -F '=' '/^version=/ {print $2}' "/data/adb/modules/playintegrityfix/module.prop")
}

log_event() {
    log_level=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$log_level] - $1" >> "$LOG_FILE"
}

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        if [ -d "/data/data/com.termux/files/usr/bin" ]; then
            log_event "$1 not found. Using Termux path." "WARN"
            echo "/data/data/com.termux/files/usr/bin/$1"
        else
            log_event "$1 not found and Termux is unavailable." "ERROR"
            exit 1
        fi
    else
        echo "$(command -v $1)"
    fi
}

JQ=$(check_tool jq)
CURL=$(check_tool curl)

get_device_name() {
    su -c "cat /data/data/com.github.furtif.furtifformaps/files/config.json" | $JQ -r ".RotomDeviceName"
}

get_json_value() {
    key=$1
    $JQ -r "$key" "$CONFIG_FILE"
}

if [ ! -f "$CONFIG_FILE" ]; then
    log_event "Config file not found at $CONFIG_FILE" "ERROR"
    exit 1
fi

DISCORD_WEBHOOK_URL=$(get_json_value ".DISCORD_WEBHOOK_URL")
ROTOM_URL=$(get_json_value ".ROTOM_URL")
CHECK_INTERVAL=$(get_json_value ".CHECK_INTERVAL")
MEMORY_THRESHOLD=$(get_json_value ".MEMORY_THRESHOLD")
ROTOM_AUTH_USER=$(get_json_value ".ROTOM_AUTH_USER")
ROTOM_AUTH_PASS=$(get_json_value ".ROTOM_AUTH_PASS")
SLEEP_APP_START=$(get_json_value ".SLEEP_APP_START")

TAB1_X=$(get_json_value ".TAP_COORDINATES[0].x")
TAB1_Y=$(get_json_value ".TAP_COORDINATES[0].y")
TAB1_SLEEP=$(get_json_value ".TAP_COORDINATES[0].sleep")

TAB2_X=$(get_json_value ".TAP_COORDINATES[1].x")
TAB2_Y=$(get_json_value ".TAP_COORDINATES[1].y")
TAB2_SLEEP=$(get_json_value ".TAP_COORDINATES[1].sleep")

TAB3_X=$(get_json_value ".TAP_COORDINATES[2].x")
TAB3_Y=$(get_json_value ".TAP_COORDINATES[2].y")
TAB3_SLEEP=$(get_json_value ".TAP_COORDINATES[2].sleep")

TAB4_X=$(get_json_value ".TAP_COORDINATES[3].x")
TAB4_Y=$(get_json_value ".TAP_COORDINATES[3].y")
TAB4_SLEEP=$(get_json_value ".TAP_COORDINATES[3].sleep")

SWIPE_START_X=$(get_json_value ".SWIPE_COORDINATES.start_x")
SWIPE_START_Y=$(get_json_value ".SWIPE_COORDINATES.start_y")
SWIPE_END_X=$(get_json_value ".SWIPE_COORDINATES.end_x")
SWIPE_END_Y=$(get_json_value ".SWIPE_COORDINATES.end_y")
SWIPE_DURATION=$(get_json_value ".SWIPE_COORDINATES.duration")
SWIPE_SLEEP=$(get_json_value ".SWIPE_COORDINATES.sleep")

if [ -z "$DISCORD_WEBHOOK_URL" ] || [ -z "$ROTOM_URL" ]; then
    log_event "Missing critical configuration values. Check your JSON file." "ERROR"
    exit 1
fi

log_event "Configuration loaded successfully." "INFO"

calculate_runtime() {
    local end_time=$(date +%s)  # Aktueller Zeitpunkt in Sekunden
    local elapsed_seconds=$((end_time - START_TIME))

    local hours=$((elapsed_seconds / 3600))
    local minutes=$(( (elapsed_seconds % 3600) / 60 ))

    echo "${hours}h ${minutes}m"
}

generate_json_payload() {
    local title="$1"
    local description="$2"
    local color="$3"
    local footer="$4"
    local fields="$5"

    if [[ -z "$fields" ]]; then
        fields="[]"
    fi

    $JQ -n \
        --arg title "$title" \
        --arg description "$description" \
        --arg footer "$footer" \
        --argjson fields "$fields" \
        --arg color "$color" \
        '{
            content: "",
            tts: false,
            embeds: [
                {
                    title: $title,
                    description: $description,
                    color: ($color | tonumber),
                    fields: $fields,
                    footer: {
                        text: $footer
                    }
                }
            ],
            components: [],
            actions: {}
        }'
}

send_discord_message() {
    local json_payload="$1"

    response=$($CURL -s -X POST -k \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$DISCORD_WEBHOOK_URL")

    http_code=$(echo "$response" | $JQ -r '.code // 200')
    if [[ $http_code -ne 200 ]]; then
        log_event "Failed to send Discord message. HTTP status: $http_code" "ERROR"
        return 1
    fi
}

check_device_status() {
    get_info
    runtime=$(calculate_runtime)
    api_success=false
    pid_check_success=false

    check_pids() {
        PidPOGO=$(pidof com.nianticlabs.pokemongo)
        PidAPK=$(pidof com.github.furtif.furtifformaps)
        if [ -n "$PidPOGO" ] && [ -n "$PidAPK" ]; then
            echo "true"
        else
            echo "false"
        fi
    }

    fetch_api_data() {
        local curl_cmd="$CURL -s --connect-timeout 7 --max-time 10"
        if [ -n "$ROTOM_AUTH_USER" ] && [ -n "$ROTOM_AUTH_PASS" ]; then
            curl_cmd="$curl_cmd --user $ROTOM_AUTH_USER:$ROTOM_AUTH_PASS"
        fi

        response=$($curl_cmd "$ROTOM_URL")
        http_code=$($curl_cmd -o /dev/null -s -w "%{http_code}" "$ROTOM_URL")

        # Prüfe, ob der HTTP-Code 200 ist und die Antwort gültiges JSON enthält
        if [ "$http_code" -ne 200 ] || ! echo "$response" | $JQ empty 2>/dev/null; then
            log_event "API request failed. HTTP $http_code" "ERROR"
            echo ""
            return 1
        fi
        echo "$response"
    }

    if [ -n "$ROTOM_URL" ]; then
        max_retries=3
        attempt=1
        api_response=""

        while [ $attempt -le $max_retries ]; do
            api_response=$(fetch_api_data)
            if [ -n "$api_response" ]; then
                break
            fi
            log_event "API request attempt $attempt failed, retrying..." "WARN"
            sleep 2
            attempt=$((attempt + 1))
        done

        if [ -n "$api_response" ]; then
            device_info=$(echo "$api_response" | $JQ -r --arg name "$DEVICE_NAME" '.devices[] | select(.origin | contains($name))')
            if [ -n "$device_info" ]; then
                is_alive=$(echo "$device_info" | $JQ -r '.isAlive')
                mem_free=$(echo "$device_info" | $JQ -r '.lastMemory.memFree')
                
                if [ "$is_alive" = "true" ] && [ "$mem_free" -ge "$MEMORY_THRESHOLD" ]; then
                    log_event "API Status OK - Memory: $mem_free | Alive: $is_alive" "INFO"
                    api_success=true
                else
                    log_event "API Alert - Memory: $mem_free | Alive: $is_alive" "WARN"
                fi
            else
                log_event "Device $DEVICE_NAME not found in API response" "WARN"
            fi
        fi
    fi

    if [ "$api_success" != "true" ]; then
        log_event "Falling back to PID check..." "WARN"
        if [ "$(check_pids)" = "true" ]; then
            pid_check_success=true
            log_event "PID Check OK - Pogo: $PidPOGO | Furtif: $PidAPK" "INFO"
        else
            log_event "PID Check FAIL - Pogo: $PidPOGO | Furtif: $PidAPK" "ERROR"
        fi
    fi

    if [ "$api_success" != "true" ] && [ "$pid_check_success" != "true" ]; then
        fields=$($JQ -n --arg name "Runtime:" --arg value "$runtime" '[{name: $name, value: $value}]')
        json_payload=$(generate_json_payload \
            "$DEVICE_NAME" \
            "Critical: Both API and PID checks failed! Restarting..." \
            "16711680" \
            "IP: $local_ip - CPU: $temperature°C" \
            "$fields"
        )
        (send_discord_message "$json_payload" &)
        
        stop_apk_tools
        start_apk_tools
        return 1
    elif [ "$api_success" != "true" ]; then
        log_event "API failed but PID check passed. Monitoring..." "WARN"
        return 2
    fi

    return 0
}

stop_apk_tools() {
    log_event "Stopping FurtifForMaps..." "INFO"
    am force-stop com.github.furtif.furtifformaps
	am force-stop com.nianticlabs.pokemongo
    sleep 5
}

start_apk_tools() {
    get_info
    log_event "Starting APK tools for $DEVICE_NAME..." "INFO"
    
    am force-stop com.github.furtif.furtifformaps
    am force-stop com.nianticlabs.pokemongo

    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    
    sleep "$SLEEP_APP_START"

    input tap "$TAB1_X" "$TAB1_Y" && sleep "$TAB1_SLEEP"
    input swipe "$SWIPE_START_X" "$SWIPE_START_Y" "$SWIPE_END_X" "$SWIPE_END_Y" "$SWIPE_DURATION" && sleep "$SWIPE_SLEEP"
    input tap "$TAB2_X" "$TAB2_Y" && sleep "$TAB2_SLEEP"
    input tap "$TAB3_X" "$TAB3_Y" && sleep "$TAB3_SLEEP"
    input tap "$TAB4_X" "$TAB4_Y" && sleep "$TAB4_SLEEP"

    log_event "Waiting for apps to stabilize..." "DEBUG"
    sleep 30

    retries=3
    success=false
    i=1
    while [ "$i" -le "$retries" ]; do
        PidPOGO=$(pidof com.nianticlabs.pokemongo)
        PidAPK=$(pidof com.github.furtif.furtifformaps)
        
        if [ -n "$PidPOGO" ] && [ -n "$PidAPK" ]; then
            success=true
            break
        else
            log_event "Attempt $i: Apps not running. Retrying full restart..." "WARN"
            sleep 5
            am force-stop com.github.furtif.furtifformaps
            am force-stop com.nianticlabs.pokemongo
            am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
            sleep "$SLEEP_APP_START"

            input tap "$TAB1_X" "$TAB1_Y" && sleep "$TAB1_SLEEP"
            input swipe "$SWIPE_START_X" "$SWIPE_START_Y" "$SWIPE_END_X" "$SWIPE_END_Y" "$SWIPE_DURATION" && sleep "$SWIPE_SLEEP"
            input tap "$TAB2_X" "$TAB2_Y" && sleep "$TAB2_SLEEP"
            input tap "$TAB3_X" "$TAB3_Y" && sleep "$TAB3_SLEEP"
            input tap "$TAB4_X" "$TAB4_Y" && sleep "$TAB4_SLEEP"

            log_event "Waiting for apps to stabilize after restart attempt $i..." "DEBUG"
            sleep 30
        fi
        i=$(expr "$i" + 1)
    done

    if [ "$success" = "true" ]; then
        fields=$($JQ -n \
            --arg name "Versions:" \
            --arg value "MapWorld: **v$mitm_version**\nPokémon GO: **v$pogo_version**\nPlay Integrity Fix: **$module_version**" \
            '[{name: $name, value: ($value | gsub("\\\\n"; "\n"))}]'
        )
        
        json_payload=$(generate_json_payload \
            "$DEVICE_NAME" \
            "Status: --=FurtiF™=-- Tools and Pokémon GO successfully launched." \
            "65280" \
            "local IP: $local_ip" \
            "$fields"
        )
        log_event "Apps verified as running. PIDs: Pogo=$PidPOGO, Furtif=$PidAPK" "INFO"
    else
        json_payload=$(generate_json_payload \
            "$DEVICE_NAME" \
            "️⚠️ Critical: Apps failed to launch after $retries attempts!" \
            "16711680" \
            "Last IP: $local_ip" \
            "[{\"name\": \"Troubleshooting\", \"value\": \"Check device logs\"}]"
        )
        log_event "App launch FAILED. PIDs: Pogo=$PidPOGO, Furtif=$PidAPK" "ERROR"
    fi

    (send_discord_message "$json_payload" &)
    START_TIME=$(date +%s)
}

log_event "main execution starts." "INFO"
sleep 30

DEVICE_NAME=$(get_device_name)

if [ -z "$DEVICE_NAME" ]; then
    log_event "Failed to retrieve RotomDeviceName from /data/data/com.github.furtif.furtifformaps/files/config.json. Check permissions or file content." "ERROR"
    exit 1
fi

log_event "Device name loaded: $DEVICE_NAME" "INFO"

start_apk_tools

while true; do
    sleep "$CHECK_INTERVAL"
    check_device_status
done
