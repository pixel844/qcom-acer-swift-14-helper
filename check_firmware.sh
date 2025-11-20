#!/bin/bash

echo "=== Qualcomm X1E Firmware Status Check ==="
echo

# Check if firmware files exist
echo "1. Checking firmware files installation..."
device_model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null)"
echo "   Device: ${device_model}"

case "$device_model" in
	"Acer Swift 14 AI (SF14-11)")
		device_path="ACER/SF14-11"
		;;
	"ASUS Vivobook S 15")
		device_path="ASUSTeK/vivobook-s15"
		;;
	"Dell XPS 13 9345")
		device_path="dell/xps13-9345"
		;;
	"HP Omnibook X 14")
		device_path="hp/omnibook-x14"
		;;
	"Lenovo ThinkPad T14s Gen 6")
		device_path="LENOVO/21N1"
		;;
	"Lenovo Yoga Slim 7x")
		device_path="LENOVO/83ED"
		;;
	"Microsoft Surface Laptop 7 (13.8 inch)")
		device_path="microsoft/Romulus"
		;;
	"Samsung Galaxy Book4 Edge")
		device_path="SAMSUNG/galaxy-book4-edge"
		;;
	*)
		echo "   ⚠ Device not recognized"
		device_path=""
		;;
esac

if [ -n "$device_path" ]; then
	fw_path="/lib/firmware/qcom/x1e80100/${device_path}"
	if [ -d "$fw_path" ]; then
		echo "   ✓ Firmware directory exists: $fw_path"
		echo "   Files present:"
		ls -lh "$fw_path" 2>/dev/null | tail -n +2 | awk '{print "     " $9 " (" $5 ")"}'
	else
		echo "   ✗ Firmware directory not found: $fw_path"
	fi
fi

echo

# Check dmesg for firmware loading
echo "2. Checking kernel logs for firmware loading..."
fw_logs=$(dmesg 2>/dev/null | grep -i "qcom.*firmware" | tail -5)
if [ -n "$fw_logs" ]; then
	echo "$fw_logs" | sed 's/^/   /'
else
	echo "   No firmware loading messages found"
fi

echo

# Check for firmware loading errors
echo "3. Checking for firmware errors..."
errors=$(dmesg 2>/dev/null | grep -i "firmware.*fail\|firmware.*error" | grep -i "qcom\|adsp\|cdsp" | tail -5)
if [ -n "$errors" ]; then
	echo "$errors" | sed 's/^/   ⚠ /'
else
	echo "   ✓ No firmware errors detected"
fi

echo

# Check remoteproc status
echo "4. Checking remoteproc subsystems status..."
if [ -d /sys/class/remoteproc ]; then
	found_rproc=0
	for rproc in /sys/class/remoteproc/remoteproc*; do
		if [ -d "$rproc" ]; then
			found_rproc=1
			name=$(cat "$rproc/name" 2>/dev/null || echo "unknown")
			state=$(cat "$rproc/state" 2>/dev/null || echo "unknown")
			echo "   $(basename "$rproc"): $name - State: $state"
		fi
	done
	if [ $found_rproc -eq 0 ]; then
		echo "   ⚠ No remoteproc devices found"
	fi
else
	echo "   ⚠ No remoteproc subsystem available"
fi

echo

# Check for ADSP/CDSP devices
echo "5. Checking DSP subsystems..."
dsp_logs=$(dmesg 2>/dev/null | grep -E "adsp|cdsp" | grep -i "boot\|start\|ready" | tail -3)
if [ -n "$dsp_logs" ]; then
	echo "$dsp_logs" | sed 's/^/   /'
else
	echo "   No DSP boot messages found"
fi

echo

# Check audio devices (ADSP often handles audio)
echo "6. Checking audio subsystem..."

# Check PipeWire
if command -v pw-cli >/dev/null 2>&1; then
	echo "   PipeWire status:"
	if systemctl --user is-active pipewire >/dev/null 2>&1 || systemctl is-active pipewire >/dev/null 2>&1; then
		echo "     ✓ PipeWire service is running"
	else
		echo "     ⚠ PipeWire service is not running"
	fi

	# Check for audio devices in PipeWire
	audio_devices=$(pw-cli ls Node 2>/dev/null | grep -E "media.class.*Audio" | wc -l)
	if [ "$audio_devices" -gt 0 ]; then
		echo "     ✓ Found $audio_devices audio node(s) in PipeWire"
	else
		echo "     ⚠ No audio nodes found in PipeWire"
	fi
else
	echo "   ⚠ PipeWire (pw-cli) not found"
fi

# Also check ALSA as fallback
if [ -d /proc/asound ]; then
	echo "   ALSA cards detected:"
	if [ -f /proc/asound/cards ]; then
		cat /proc/asound/cards 2>/dev/null | sed 's/^/     /' || echo "     None"
	else
		echo "     No cards file found"
	fi
else
	echo "   ⚠ No ALSA subsystem found"
fi

echo

# Check for processes blocking audio devices
echo "7. Checking for processes using audio devices..."
if command -v lsof >/dev/null 2>&1; then
	echo "   Processes with audio device files open:"
	audio_procs=$(lsof 2>/dev/null | grep -E "/dev/snd|/dev/dsp|pipewire" | awk '{print $1, $2, $9}' | sort -u)
	if [ -n "$audio_procs" ]; then
		echo "$audio_procs" | sed 's/^/     /'
		echo
		echo "   Summary by process:"
		echo "$audio_procs" | awk '{print $1}' | sort | uniq -c | sed 's/^/     /'
	else
		echo "     No processes currently accessing audio devices"
	fi
elif command -v fuser >/dev/null 2>&1; then
	echo "   Using fuser to check audio devices:"
	for dev in /dev/snd/* /dev/dsp* 2>/dev/null; do
		if [ -e "$dev" ]; then
			procs=$(fuser "$dev" 2>/dev/null)
			if [ -n "$procs" ]; then
				echo "     $dev: PIDs $procs"
				for pid in $procs; do
					pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
					echo "       - PID $pid: $pname"
				done
			fi
		fi
	done
else
	echo "   ⚠ Neither lsof nor fuser available - cannot check for blocking processes"
	echo "   Install lsof with: sudo apt install lsof  (or equivalent for your distro)"
fi

echo
echo "=== Summary ==="
echo "Run 'dmesg | grep -i firmware' for detailed firmware loading logs"
echo "Run 'journalctl -k | grep -i firmware' for persistent logs"
