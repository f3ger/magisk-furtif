#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
#!/system/bin/sh
MODDIR=${0%/*}

while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done
sleep 5

check_device_status() {
    PidPOGO=$(pidof com.nianticlabs.pokemongo)
    PidAPK=$(pidof com.github.furtif.furtifformaps)
    if [[ -z "$PidPOGO" || -z "$PidAPK" ]]; then
        return 1  
    fi
    return 0  
}

close_apps_if_offline_and_start_it() {
    am force-stop com.github.furtif.furtifformaps
    am force-stop com.nianticlabs.pokemongo
    sleep 5
    start_apk_tools
}

start_apk_tools() {
    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    sleep 10
    input tap 650 470
    sleep 25
    input swipe 895 539 895 119 300
    sleep 10
    input tap 860 600
    sleep 20
    input tap 640 240
    sleep 10
    input tap 640 360
    sleep 15
}

sleep 10

start_apk_tools

sleep 300

while true; do
    if ! check_device_status; then
        close_apps_if_offline_and_start_it
        sleep 5
        continue
    fi
    sleep 300
done
