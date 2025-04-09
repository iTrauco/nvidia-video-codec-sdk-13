#!/bin/bash
# collect_system_info.sh - Precision system audit script w/ accurate motherboard + ECC handling

OUTPUT_FILE="system_info_$(hostname)_$(date +%Y%m%d_%H%M).txt"

{
  echo "🖥️ SYSTEM OVERVIEW -----------------------------"
  echo "Hostname     : $(hostname)"
  echo "Date         : $(date)"
  echo "OS           : $(lsb_release -d | cut -f2-)"
  echo

  echo "🏭 SYSTEM IDENTIFICATION ------------------------"
  sudo dmidecode -t system | awk -v show_sensitive=$SHOW_SENSITIVE '
    /Manufacturer:/ || /Product Name:/ {
      print $0
    }
    /Serial Number:/ || /UUID:/ {
      if (show_sensitive == "true") {
        print $0
      } else {
        split($0, parts, ":")
        printf "%s: ****REDACTED****\n", parts[1]
      }
    }'
  echo

  echo "📋 BASEBOARD / MOTHERBOARD ----------------------"
  sudo dmidecode -t baseboard | awk -v show_sensitive=$SHOW_SENSITIVE '
    /Manufacturer:/ || /Product Name:/ || /Version:/ {
      if ($2 != "Default" && $3 != "string") print $0
    }
    /Serial Number:/ {
      if (show_sensitive == "true") {
        print $0
      } else {
        split($0, parts, ":")
        printf "%s: ****REDACTED****\n", parts[1]
      }
    }'
  echo


  echo "🧬 CPU INFO ------------------------------------"
  lscpu
  echo

  echo "📦 RAM SLOT MAP --------------------------------"
  echo "🧩 DIMM SLOT LAYOUT (by physical locator + node)"
  echo "-----------------------------------------------"
  sudo dmidecode --type 17 | awk '
    BEGIN { slot = 0 }
    /^Memory Device$/ { in_device = 1; next }
    in_device && /Locator:/ { locator = $2; next }
    in_device && /Bank Locator:/ { bank = $3; next }
    in_device && /Size:/ {
      size = $2 " " $3;
      if ($2 == "No") { size = "Empty" }
      next
    }
    in_device && /Type:/ { type = $2; next }
    in_device && /Speed:/ { speed = $2 " " $3; next }
    in_device && /Configured Memory Speed:/ { config_speed = $4 " " $5; next }
    in_device && /Manufacturer:/ { manu = $2; next }
    in_device && /Part Number:/ { part = $0; gsub("^[[:space:]]*Part Number:[[:space:]]*", "", part); next }
    in_device && /^$/ {
      printf "Slot %-5s | %-6s | %-10s | %-7s | %-10s | %-10s | %s\n", locator, bank, size, type, speed, config_speed, part
      in_device = 0
    }'
  echo

  echo "🧠 USABLE SYSTEM RAM ----------------------------"
  free -h | awk '/Mem:/ {print "Total:", $2, "| Used:", $3, "| Free:", $4}'
  echo

  echo "🎮 NVIDIA GPU DETAILS ---------------------------"

   echo "📊 GPU DIAGNOSTIC PROFILE — METRICS & ENGINEERING CONTEXT---------------------"
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,clocks.gr,clocks.sm,temperature.gpu,power.draw,power.limit,utilization.gpu \
      --format=csv,noheader,nounits | awk -F, '{
        printf "🎮 Model              : %s\n", $1
        printf "💾 VRAM Total         : %s MiB\n", $2
        printf "📂 VRAM Used          : %s MiB\n", $3
        printf "📭 VRAM Free          : %s MiB\n", $4
        printf "⚙️ Graphics Clock      : %s MHz\n", $5
        printf "📉 SM Clock           : %s MHz\n", $6
        printf "🌡️ Temp               : %s °C\n", $7
        printf "⚡ Power Draw          : %s W\n", $8
        printf "🔋 Power Limit         : %s W\n", $9
        printf "📈 GPU Utilization     : %s %%\n", $10
      }'
    echo

    echo "📘 EXPLAINER ---------------------------------------------"
    echo "🎮 Model            : Your actual GPU model (RTX A5500)"
    echo "💾 VRAM Total       : Max video memory. Impacts large textures, video frames, and ML batch sizes."
    echo "📂 VRAM Used        : How much memory your apps are currently using (OBS, browser, etc.)"
    echo "⚙️ Graphics Clock    : Real-time frequency of graphics core (affects FPS & frame rendering speed)."
    echo "📉 SM Clock         : Streaming Multiprocessors (used in ML, CUDA, shaders)"
    echo "🌡️ Temp             : Ideal under 80°C. Above 85°C may throttle performance."
    echo "⚡ Power Draw        : Real-time power usage. Spikes under load like 3D rendering or ML."
    echo "🔋 Power Limit       : The GPU’s firmware-enforced power cap (can sometimes be adjusted)."
    echo "📈 GPU Utilization   : % of cores in use — 0–100% depending on workload. ~20–60% under OBS."
  else
    echo "nvidia-smi not found."
  fi
  echo


  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,driver_version,serial,pci.bus_id,memory.total,memory.used,memory.free,temperature.gpu,clocks.gr,clocks.sm,power.draw,power.limit \
      --format=csv,noheader,nounits
    echo

    echo "🧪 NVIDIA ECC STATUS -----------------------------"
    if nvidia-smi -q | grep -q "Ecc Mode"; then
      nvidia-smi -q | grep -A6 "Ecc Mode"
    else
      echo "ECC Mode: Not supported on this GPU or not enabled."
    fi
  else
    echo "nvidia-smi not found."
  fi
  echo

  echo "🔧 NVIDIA SETTINGS SNAPSHOT ---------------------"
  if command -v nvidia-settings &>/dev/null; then
    nvidia-settings -q all 2>/dev/null | grep -E 'GPUCurrentClockFreqs|GPUFanControlState|GPUCurrentFanSpeed|GPUCurrentFanSpeedRPM|GPUPowerSource|GPUCurrentClockFreqsString'
  else
    echo "nvidia-settings not available (no GUI or not installed)."
  fi
  echo

  echo "🌐 NETWORK INTERFACES ---------------------------"
  ip -o link show | awk -F': ' '{print $2}' | while read iface; do
    echo "Interface: $iface"
    ethtool $iface 2>/dev/null | grep -E "Speed|Duplex|Link detected"
    echo
  done

} | tee "$OUTPUT_FILE"
