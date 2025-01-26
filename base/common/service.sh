#!/system/bin/sh
MODDIR=${0%/*}

while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done

# Warte zusätzlich auf Netzwerkverbindung und kritische Dienste
MAX_WAIT=30  # Maximale Wartezeit in Sekunden (als Fallback)
start_time=$(date +%s)
while true; do
    # Prüfe, ob Netzwerkverbindung besteht
    if ip route get 1.1.1.1 &> /dev/null && \
       ping -c1 1.1.1.1 &> /dev/null && \
       [ "$(getprop service.bootanim.exit)" = "1" ]; then
        break
    fi

    # Timeout nach MAX_WAIT Sekunden
    if [ $(($(date +%s) - start_time)) -ge $MAX_WAIT ]; then
        log_event "Timeout: Network/services not ready after $MAX_WAIT seconds." "WARN"
        break
    fi
    sleep 2
done

local_ip="$(ip route get 1.1.1.1 | awk '{print $7}')"

# JSON-Konfigurationsdatei
CONFIG_FILE="/sdcard/Download/config.json"
LOG_FILE="/sdcard/Download/device_monitor.log"

get_info() {
pogo_version="$(dumpsys package com.nianticlabs.pokemongo | awk -F "=" '/versionName/ {print $2}')"
mitm_version="$(dumpsys package com.github.furtif.furtifformaps | awk -F "=" '/versionName/ {print $2}')"
temperature="$(cat /sys/class/thermal/thermal_zone0/temp | awk '{print substr($0, 1, length($0)-3)}')"
module_version=$(awk -F '=' '/^version=/ {print $2}' "/data/adb/modules/playintegrityfix/module.prop")
}

trim_logs() {
    MAX_LINES=1000  # Maximale Anzahl der Logzeilen

    if [ -f "$LOG_FILE" ]; then
        log_lines=$(wc -l < "$LOG_FILE")
        if [ "$log_lines" -ge "$MAX_LINES" ]; then
            tail -n "$MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp"  # Behalten Sie nur die letzten 1000 Zeilen
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
            log_event "Log file trimmed to the last $MAX_LINES lines." "INFO"
        fi
    fi
}

# Funktion: Ereignisse protokollieren
log_event() {
    log_level=$2
    trim_logs
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$log_level] - $1" >> "$LOG_FILE"
}

# Funktion: Tool-Verfügbarkeit prüfen
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

# Funktion: RotomDeviceName auslesen
get_device_name() {
    su -c "cat /data/data/com.github.furtif.furtifformaps/files/config.json" | $JQ -r ".RotomDeviceName"
}

# Funktion: JSON auslesen
get_json_value() {
    key=$1
    $JQ -r "$key" "$CONFIG_FILE"
}

# Überprüfen, ob die JSON-Konfigurationsdatei existiert
if [ ! -f "$CONFIG_FILE" ]; then
    log_event "Config file not found at $CONFIG_FILE" "ERROR"
    exit 1
fi

# Variablen aus JSON-Datei laden
DISCORD_WEBHOOK_URL=$(get_json_value ".DISCORD_WEBHOOK_URL")
ROTOM_URL=$(get_json_value ".ROTOM_URL")
CHECK_INTERVAL=$(get_json_value ".CHECK_INTERVAL")
MEMORY_THRESHOLD=$(get_json_value ".MEMORY_THRESHOLD")
ROTOM_AUTH_USER=$(get_json_value ".ROTOM_AUTH_USER")
ROTOM_AUTH_PASS=$(get_json_value ".ROTOM_AUTH_PASS")
SLEEP_APP_START=$(get_json_value ".SLEEP_APP_START")

# Tap-Koordinaten laden
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

# Swipe-Koordinaten laden
SWIPE_START_X=$(get_json_value ".SWIPE_COORDINATES.start_x")
SWIPE_START_Y=$(get_json_value ".SWIPE_COORDINATES.start_y")
SWIPE_END_X=$(get_json_value ".SWIPE_COORDINATES.end_x")
SWIPE_END_Y=$(get_json_value ".SWIPE_COORDINATES.end_y")
SWIPE_DURATION=$(get_json_value ".SWIPE_COORDINATES.duration")
SWIPE_SLEEP=$(get_json_value ".SWIPE_COORDINATES.sleep")

# Überprüfen, ob wichtige Variablen geladen wurden
if [ -z "$DISCORD_WEBHOOK_URL" ] || [ -z "$ROTOM_URL" ]; then
    log_event "Missing critical configuration values. Check your JSON file." "ERROR"
    exit 1
fi

log_event "Configuration loaded successfully." "INFO"

# Dynamische Intervalle
BASE_CHECK_INTERVAL="$CHECK_INTERVAL"  # Ursprünglicher Wert aus der Config
CURRENT_CHECK_INTERVAL="$BASE_CHECK_INTERVAL"
STABLE_THRESHOLD=5  # Anzahl erfolgreicher Checks, bevor Intervall erhöht wird
stable_counter=0

calculate_runtime() {
    local end_time=$(date +%s)  # Aktueller Zeitpunkt in Sekunden
    local elapsed_seconds=$((end_time - START_TIME))

    local hours=$((elapsed_seconds / 3600))
    local minutes=$(( (elapsed_seconds % 3600) / 60 ))

    echo "${hours}h ${minutes}m"
}

# Funktion zur Generierung von Payloads
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

# Funktion zum Senden von Nachrichten
send_discord_message() {
    local json_payload="$1"

    # Debugging: JSON Payload anzeigen
    #log_event "JSON Payload: $json_payload" "DEBUG"

    # cURL-Anfrage senden
    response=$($CURL -s -X POST -k \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$DISCORD_WEBHOOK_URL")

    # Debugging: Discord-Antwort loggen
    log_event "Discord response: $response" "DEBUG"

    # Optional: Fehlerbehandlung basierend auf der Antwort
    http_code=$(echo "$response" | $JQ -r '.code // 200') # Falls kein Code vorhanden, Standard 200
    if [[ $http_code -ne 200 ]]; then
        log_event "Failed to send Discord message. HTTP status: $http_code" "ERROR"
        return 1
    fi
}

# Funktion: Gerätestatus prüfen
check_device_status() {
    get_info
    runtime=$(calculate_runtime)

    if [ -z "$ROTOM_URL" ]; then
        log_event "ROTOM_URL not set. Falling back to PID-based status check." "WARN"
        
        # PID-Überprüfung, ob Apps laufen
        PidPOGO=$(pidof com.nianticlabs.pokemongo)
        PidAPK=$(pidof com.github.furtif.furtifformaps)

        if [[ -z "$PidPOGO" || -z "$PidAPK" ]]; then
            # Generiere JSON für fehlende Prozesse
            fields=$($JQ -n --arg name "Runtime:" --arg value "$runtime" '[{name: $name, value: $value}]')
            json_payload=$(generate_json_payload \
                "$DEVICE_NAME" \
                "Alert: Tools are offline. Missing processes." \
                "16711680" \
                "local IP: $local_ip - CPU temp: $temperature°C" \
                "$fields"
            )

            send_discord_message "$json_payload"

            log_event "Device is offline. PidPOGO=$PidPOGO, PidAPK=$PidAPK. Runtime: ${runtime}" "ERROR"
            stop_apk_tools
            start_apk_tools
        else
            log_event "Device $DEVICE_NAME is online. PidPOGO=$PidPOGO, PidAPK=$PidAPK." "INFO"
        fi
        return
    fi

    # Wenn ROTOM_URL gesetzt ist, prüfen wir die API-Verbindung
    if [ -n "$ROTOM_AUTH_USER" ] && [ -n "$ROTOM_AUTH_PASS" ]; then
        response=$($CURL -s --user "$ROTOM_AUTH_USER:$ROTOM_AUTH_PASS" --connect-timeout 5 --max-time 10 "$ROTOM_URL")
    else
        response=$($CURL -s --connect-timeout 5 --max-time 10 "$ROTOM_URL")
    fi

    if [ -z "$response" ]; then
        # Generiere JSON für fehlende API-Antwort
        json_payload=$(generate_json_payload \
            "$DEVICE_NAME" \
            "Warning: Could not retrieve status from API. Falling back to PID check." \
            "16776960" \
            "local IP: $local_ip" \
            "[]"
        )

        send_discord_message "$json_payload"
        log_event "Failed to retrieve status from API. Falling back to PID check. Runtime: ${runtime}" "ERROR"

        # Fallback zu PID-Überprüfung
        PidPOGO=$(pidof com.nianticlabs.pokemongo)
        PidAPK=$(pidof com.github.furtif.furtifformaps)

        if [[ -z "$PidPOGO" || -z "$PidAPK" ]]; then
            # Generiere JSON für fehlende Prozesse
            fields=$($JQ -n --arg name "Runtime:" --arg value "$runtime" '[{name: $name, value: $value}]')
            json_payload=$(generate_json_payload \
                "$DEVICE_NAME" \
                "Alert: Tools are offline. Missing processes. ** **" \
                "16711680" \
                "local IP: $local_ip - CPU temp: $temperature°C" \
                "$fields"
            )

            send_discord_message "$json_payload"
            log_event "Device is offline. PidPOGO=$PidPOGO, PidAPK=$PidAPK. Runtime: ${runtime}" "ERROR"
            stop_apk_tools
            start_apk_tools
        else
            log_event "Device $DEVICE_NAME is online. PidPOGO=$PidPOGO, PidAPK=$PidAPK." "INFO"
        fi
        return
    fi

    # Überprüfen, ob das Gerät in der API gefunden wurde
    device_info=$(echo "$response" | $JQ -r --arg name "$DEVICE_NAME" '.devices[] | select(.origin | contains($name))')

    if [ -z "$device_info" ]; then
        # Generiere JSON für nicht gefundenes Gerät
        json_payload=$(generate_json_payload \
            "$DEVICE_NAME" \
            "️Warning: Device not found in API response." \
            "16776960" \
            "local IP: $local_ip" \
            "[]"
        )

        send_discord_message "$json_payload"
        log_event "Device $DEVICE_NAME not found in API response. Runtime: ${runtime}" "WARN"
        return
    fi

    # API-Daten verarbeiten
    is_alive=$(echo "$device_info" | $JQ -r '.isAlive')
    mem_free=$(echo "$device_info" | $JQ -r '.lastMemory.memFree')

    if [ "$is_alive" = "false" ] || [ "$mem_free" -lt "$MEMORY_THRESHOLD" ]; then
        # Generiere JSON für Offline- oder Speichermangel-Status
        fields=$($JQ -n --arg name "Runtime:" --arg value "$runtime" '[{name: $name, value: $value}]')
        json_payload=$(generate_json_payload \
            "$DEVICE_NAME" \
            "Alert: Device is offline or has low memory. Restarting APK tools." \
            "16711680" \
            "local IP: $local_ip - CPU: $temperature°C" \
            "$fields"
        )

        send_discord_message "$json_payload"
        log_event "Device $DEVICE_NAME offline or low memory. Restarting APK tools. Runtime: ${runtime}" "ERROR"
        stop_apk_tools
        start_apk_tools
		return 1
    else
        log_event "Device $DEVICE_NAME status OK: Runtime ${runtime} - Memory $mem_free" "INFO"
		return 0
    fi
}

# Funktion: Apps stoppen
stop_apk_tools() {
    log_event "Stopping FurtifForMaps..." "INFO"
    am force-stop com.github.furtif.furtifformaps
	am force-stop com.nianticlabs.pokemongo
    sleep 5
}

# Funktion: App starten und Aktionen ausführen
start_apk_tools() {
    get_info
    log_event "Starting APK tools for $DEVICE_NAME..." "INFO"
    am force-stop com.github.furtif.furtifformaps
    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    sleep "$SLEEP_APP_START"

    # Tab1
    input tap "$TAB1_X" "$TAB1_Y"
    sleep "$TAB1_SLEEP"

    # Swipe
    input swipe "$SWIPE_START_X" "$SWIPE_START_Y" "$SWIPE_END_X" "$SWIPE_END_Y" "$SWIPE_DURATION"
    sleep "$SWIPE_SLEEP"

    # Tab2
    input tap "$TAB2_X" "$TAB2_Y"
    sleep "$TAB2_SLEEP"

    # Tab3
    input tap "$TAB3_X" "$TAB3_Y"
    sleep "$TAB3_SLEEP"

    # Tab4
    input tap "$TAB4_X" "$TAB4_Y"
    sleep "$TAB4_SLEEP"

# Dynamische Felder erstellen
    fields=$($JQ -n \
        --arg name "Versions:" \
        --arg value "Mapworld: **v$mitm_version**\nPokémon GO: **v$pogo_version**\nPlay Integrity Fix: **$module_version**" \
        '[{name: $name, value: ($value | gsub("\\\\n"; "\n"))}]' \
)

# Nutzlast generieren
    json_payload=$(generate_json_payload \
        "$DEVICE_NAME" \
        "Status: --=FurtiF™=-- Tools and Pokémon GO successfully launched." \
        "65280" \
        "local IP: $local_ip" \
        "$fields"
)
    send_discord_message "$json_payload"
    log_event "FurtifForMaps started and actions performed." "INFO"
    START_TIME=$(date +%s)
    log_event "App start time set to $(date -d @$START_TIME '+%Y-%m-%d %H:%M:%S')." "DEBUG"
}

# Hauptausführung
log_event "Script started." "INFO"
sleep 30  # Zusätzliche Startverzögerung
# RotomDeviceName aus der Datei lesen
DEVICE_NAME=$(get_device_name)

if [ -z "$DEVICE_NAME" ]; then
    log_event "Failed to retrieve RotomDeviceName from /data/data/com.github.furtif.furtifformaps/files/config.json. Check permissions or file content." "ERROR"
    exit 1
fi

log_event "Device name loaded: $DEVICE_NAME" "INFO"


start_apk_tools

sleep 60

while true; do
    check_device_status
    check_result=$?  # Speichere den Rückgabewert

    if [ "$check_result" -eq 0 ]; then  # Erfolg
        stable_counter=$((stable_counter + 1))
        if [ "$stable_counter" -ge "$STABLE_THRESHOLD" ]; then
            CURRENT_CHECK_INTERVAL=$((BASE_CHECK_INTERVAL * 2))  # Intervall verdoppeln
            log_event "System stable. Increasing check interval to $CURRENT_CHECK_INTERVAL seconds." "INFO"
            stable_counter=0  # Reset Counter
        fi
    else  # Fehler
        stable_counter=0
        CURRENT_CHECK_INTERVAL="$BASE_CHECK_INTERVAL"  # Zurück zum Basisintervall
        log_event "System unstable. Resetting check interval to $CURRENT_CHECK_INTERVAL seconds." "WARN"
    fi

    sleep "$CURRENT_CHECK_INTERVAL"
done
