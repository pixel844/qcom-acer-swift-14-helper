#!/bin/bash

# Remoteproc Manager Script for Fedora 43 on Snapdragon X Elite
# Manages Qualcomm ADSP and other remote processors

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "==================================="
echo "Remote Processor Manager"
echo "Snapdragon X Elite Edition"
echo "==================================="
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Check if remoteproc devices exist
if ! ls /sys/class/remoteproc/remoteproc* >/dev/null 2>&1; then
    echo -e "${RED}No remoteproc devices found on this system${NC}"
    exit 1
fi

echo "=== System Information ==="
echo -e "${BLUE}Kernel:${NC} $(uname -r)"
echo -e "${BLUE}Architecture:${NC} $(uname -m)"
echo -e "${BLUE}Platform:${NC} Snapdragon X Elite"
echo

# Check for Qualcomm firmware
echo "=== Checking Qualcomm Firmware ==="
if [ -d "/lib/firmware/qcom" ]; then
    echo -e "${GREEN}Qualcomm firmware directory exists${NC}"
    ADSP_FW_COUNT=$(find /lib/firmware/qcom -name "*adsp*" -o -name "*cdsp*" | wc -l)
    echo "Found $ADSP_FW_COUNT DSP firmware files"
else
    echo -e "${RED}Qualcomm firmware directory NOT found${NC}"
fi
echo

echo "=== Current Status of Remote Processors ==="
echo
for i in /sys/class/remoteproc/remoteproc*; do
    if [ -d "$i" ]; then
        NAME=$(cat "$i/name" 2>/dev/null || echo "Unknown")
        STATE=$(cat "$i/state" 2>/dev/null || echo "N/A")
        FIRMWARE=$(cat "$i/firmware" 2>/dev/null || echo "N/A")
        
        echo -e "${YELLOW}$(basename $i)${NC}"
        echo "  Name:     $NAME"
        echo "  State:    $STATE"
        echo "  Firmware: $FIRMWARE"
        
        # Check if firmware file actually exists
        if [ "$FIRMWARE" != "N/A" ] && [ -n "$FIRMWARE" ]; then
            if [ -f "/lib/firmware/$FIRMWARE" ]; then
                echo -e "  File:     ${GREEN}EXISTS${NC}"
            else
                echo -e "  File:     ${RED}MISSING${NC} (/lib/firmware/$FIRMWARE)"
            fi
        fi
        echo
    fi
done

echo "=== Attempting to Start Remote Processors ==="
echo

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_DEVICES=()

for i in /sys/class/remoteproc/remoteproc*/state; do
    DEVICE=$(dirname "$i")
    DEVICE_NAME=$(basename "$DEVICE")
    NAME=$(cat "$DEVICE/name" 2>/dev/null || echo "Unknown")
    CURRENT_STATE=$(cat "$i" 2>/dev/null || echo "unknown")
    FIRMWARE=$(cat "$DEVICE/firmware" 2>/dev/null || echo "")
    
    echo -n "Starting $DEVICE_NAME ($NAME)... "
    
    # If already running, stop it first
    if [ "$CURRENT_STATE" = "running" ]; then
        echo "stop" > "$i" 2>/dev/null || true
        sleep 0.5
    fi
    
    # Try to start
    if echo "start" > "$i" 2>/dev/null; then
        echo -e "${GREEN}SUCCESS${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}FAILED${NC}"
        ((FAIL_COUNT++))
        FAILED_DEVICES+=("$DEVICE_NAME:$NAME:$FIRMWARE")
    fi
done

echo
echo "==================================="
echo "Summary:"
echo "  Success: $SUCCESS_COUNT"
echo "  Failed:  $FAIL_COUNT"
echo "==================================="

if [ $FAIL_COUNT -gt 0 ]; then
    echo
    echo -e "${YELLOW}=== Detailed Diagnosis ===${NC}"
    echo
    
    # Analyze each failed device
    for device_info in "${FAILED_DEVICES[@]}"; do
        IFS=':' read -r device name firmware <<< "$device_info"
        echo -e "${BLUE}Analyzing $device ($name):${NC}"
        
        if [ -z "$firmware" ]; then
            echo -e "  ${RED}→ No firmware specified in device${NC}"
        elif [ ! -f "/lib/firmware/$firmware" ]; then
            echo -e "  ${RED}→ Firmware file missing: /lib/firmware/$firmware${NC}"
        else
            echo -e "  ${YELLOW}→ Firmware exists but failed to load${NC}"
        fi
        echo
    done
    
    # Check dmesg for recent errors
    echo -e "${BLUE}Recent kernel messages (remoteproc/ADSP):${NC}"
    dmesg | grep -i -E "(remoteproc|adsp|cdsp|qcom)" | tail -n 25
    
    echo
    echo -e "${YELLOW}=== Fixes for Snapdragon X Elite ADSP ===${NC}"
    echo
    echo "1. Install Qualcomm firmware (if available):"
    echo "   sudo dnf install linux-firmware"
    echo
    echo "2. Check if firmware-manager has Snapdragon X Elite support:"
    echo "   sudo dnf install linux-firmware-snapdragon"
    echo "   (Package name may vary)"
    echo
    echo "3. For Snapdragon X Elite, you may need vendor-specific firmware:"
    echo "   - Check your device manufacturer's Linux support page"
    echo "   - Windows firmware may need to be extracted and converted"
    echo
    echo "4. Verify device tree and kernel support:"
    echo "   dmesg | grep -i 'snapdragon\\|qualcomm\\|x1e80100'"
    echo
    echo "5. Check if running latest kernel:"
    echo "   sudo dnf update kernel"
    echo "   (Snapdragon X Elite support is newer, may need kernel 6.9+)"
    echo
    echo "6. Manual firmware check:"
    echo "   ls -la /lib/firmware/qcom/"
    echo
    echo -e "${RED}NOTE: Snapdragon X Elite Linux support is still maturing.${NC}"
    echo "Some functionality may require newer kernels or vendor firmware."
    echo
    exit 1
fi

echo -e "${GREEN}All remote processors started successfully!${NC}"
exit 0
