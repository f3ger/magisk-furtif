# Device Monitor Service for --=FurtiF™=-- Tools

A robust monitoring script for Android devices running --=FurtiF™=-- Tools.  
**Version 2.0** | Universal Device Support

---

## 📋 Prerequisites

### 1. **Required Tools**  
- `jq` and `curl` must be installed on the device.  
  - **Pre-installed on PoGoROM devices** (no action needed):  
    - ✅ **TX9s**  
    - ✅ **X96mini**
    - ✅ **A95XF1** 
    - ✅ **H96max V11 RK3318 (Android 11)**  
    These devices already include the tools via the [ClawOfDead PoGoROM](https://github.com/ClawOfDead/ATVRoms/releases) and [Andis PoGoROM](https://github.com/andi2022/PoGoRom/releases) repository.  

  - **For other devices**: Install via Termux (see below).
    - ✅ **H96max v13 RK3528 (Android 13)**
    - ✅ **Rasberry Pi 4/5 (Android 13)**

---

## 📥 Installation PoGoROM Devices

### Method 1: Magisk Manager  
1. Download the module ZIP:  
   `MagMagiskFurtif-atv-2.0.zip`  
2. Open **Magisk Manager** → **Modules** → **Install from storage**.  
3. Select the ZIP and reboot.  

### Method 2: PixelFlasher (Advanced)  
1. Load the ZIP in PixelFlasher.  
2. Flash the module and reboot.  

---

## ⚙️ Configuration

1. **Edit `config.json`**:  
   - Update `DISCORD_WEBHOOK_URL`, `TAP_COORDINATES`, etc.  
   - Use `config.example.json` as a template.  

2. **Place `config.json`**:  
   Copy to:
   ```
   /sdcard/Download/
   ````  
---
## 📥 Installation for Non-PoGoROM Devices
### Step 1: Install Termux
Download Termux from F-Droid (recommended) or the Play Store.

### Step 2: Install jq and curl
Open Termux and run:
```
pkg update && pkg upgrade -y
pkg install jq curl -y
``` 
### Step 3: Verify Installation
Ensure the tools are accessible:
```
jq --version && curl --version
```
## ⚙️ Configuration
1. **Edit `config.json`**:  
   - Update `DISCORD_WEBHOOK_URL`, `ROTOM_URL`, etc.  
   - Use `config.example.json` as a template.  

2. **Place `config.json`**:  
   Copy to:
   ```
   /sdcard/Download/
   ````  

### Install the Magisk Module
## Method 1: Magisk Manager  
1. Download the module ZIP:  
   `MagMagiskFurtif-atv-2.0.zip`  
2. Open **Magisk Manager** → **Modules** → **Install from storage**.  
3. Select the ZIP and reboot.  

## Method 2: PixelFlasher (Advanced)  
1. Load the ZIP in PixelFlasher.  
2. Flash the module and reboot.  

---
