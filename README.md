# MagiskFurtif

## Description

Runs apk-tools on boot with magisk. 

## Instructions

1. edit the config file (magisk-furtif.json)
 - Device Name
 - edit tab cords (In the example config the values ​​of a TX9s are stored)

2. push config file (magisk-furtif.json) to /sdcard/Download

3. Flash the zip for your platform using TWRP or Magisk Manager.

## example configuration

H96max V11(Android 11) RK3318

    "start_coordinates": {
        "tap1": { "x": 945, "y": 665, "sleep": 10 },
        "swipe": { "x1": 1340, "y1": 890, "x2": 1340, "y2": 295, "duration": 300, "sleep": 35 },
        "tap2": { "x": 1295, "y": 970, "sleep": 20 },
        "tap3": { "x": 945, "y": 325, "sleep": 10 },
        "tap4": { "x": 945, "y": 570, "sleep": 15 }
    }
