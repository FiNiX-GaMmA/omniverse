#!/usr/bin/env python3
import re
import subprocess
import threading
import time

# ANSI color codes for formatting terminal output
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
MAGENTA = "\033[95m"
RED = "\033[91m"
BLUE = "\033[94m"


def get_screen_size():
    """Runs `adb shell wm size` and returns (width, height)."""
    try:
        output = (
            subprocess.check_output(["adb", "shell", "wm", "size"])
            .decode("utf-8")
            .strip()
        )
        match = re.search(r"Physical size:\s*(\d+)x(\d+)", output)
        if match:
            return int(match.group(1)), int(match.group(2))
    except Exception as e:
        print(f"{RED}Warning: Failed to get screen size via adb: {e}{RESET}")
    return 1440, 3120  # Default fallback resolution


def find_touchscreen_device():
    """Runs `adb shell getevent -p` to find the device path for the touchscreen, and its min/max ranges."""
    try:
        output = subprocess.check_output(["adb", "shell", "getevent", "-p"]).decode(
            "utf-8"
        )
    except Exception as e:
        print(
            f"{RED}Error: Failed to run getevent -p. Is the device connected? {e}{RESET}"
        )
        return None, 4095, 4095

    devices = output.split("add device ")
    touch_device = None
    max_x = 4095
    max_y = 4095

    for d in devices:
        if not d.strip():
            continue
        lines = d.splitlines()
        dev_path_match = re.match(r"\d+:\s*(/dev/input/event\d+)", lines[0])
        if not dev_path_match:
            continue
        dev_path = dev_path_match.group(1)

        # Check if the device is a touchscreen or has absolute coordinates 0035 (X) and 0036 (Y)
        has_touch = False
        temp_max_x = None
        temp_max_y = None

        for line in lines:
            if "sec_touchscreen" in line.lower() or "touchscreen" in line.lower():
                has_touch = True

            # Look for ABS_MT_POSITION_X (0035) range
            x_match = re.search(
                r"0035\s*:\s*value\s+\d+,\s*min\s+\d+,\s*max\s+(\d+)", line
            )
            if x_match:
                temp_max_x = int(x_match.group(1))
                has_touch = True

            # Look for ABS_MT_POSITION_Y (0036) range
            y_match = re.search(
                r"0036\s*:\s*value\s+\d+,\s*min\s+\d+,\s*max\s+(\d+)", line
            )
            if y_match:
                temp_max_y = int(y_match.group(1))
                has_touch = True

        if has_touch:
            touch_device = dev_path
            if temp_max_x is not None:
                max_x = temp_max_x
            if temp_max_y is not None:
                max_y = temp_max_y
            break

    # If not found but we saw event8 is named sec_touchscreen
    if not touch_device:
        print(
            f"{YELLOW}Warning: Touchscreen not found in getevent list, using default /dev/input/event8{RESET}"
        )
        touch_device = "/dev/input/event8"

    return touch_device, max_x, max_y


def logcat_thread():
    """Reads adb logcat and prints formatted API logs."""
    print(f"{BLUE}info: Launching Logcat listener...{RESET}")
    # Clear logcat buffer first to avoid massive backlog
    _ = subprocess.run(["adb", "logcat", "-c"])

    # We read entire logcat and filter. This handles app restarts.
    proc = subprocess.Popen(
        ["adb", "logcat", "-v", "time"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    if proc.stdout is None:
        print(f"{RED}Error: Failed to open logcat stdout stream.{RESET}")
        return

    try:
        for line in iter(proc.stdout.readline, ""):
            if "[API REQUEST]" in line:
                # Format: I/flutter (1234): [API REQUEST] GET https://...
                parts = line.split("[API REQUEST]")
                content = parts[-1].strip()
                print(f"{GREEN}{BOLD}🟢 [API REQUEST]{RESET} {content}")
            elif "[API RESPONSE]" in line:
                parts = line.split("[API RESPONSE]")
                content = parts[-1].strip()
                # Emphasize status code if possible
                print(f"{CYAN}{BOLD}🔵 [API RESPONSE]{RESET} {content}")
            elif "[WEBVIEW" in line or "[VIDSRC" in line:
                # Match [WEBVIEW LOAD], [WEBVIEW NAVIGATE], [VIDSRC LOAD], [VIDSRC NAVIGATE]
                tag_match = re.search(r"(\[(WEBVIEW|VIDSRC)\s+[A-Z]+\])", line)
                if tag_match:
                    tag = tag_match.group(1)
                    parts = line.split(tag)
                    content = parts[-1].strip()
                    print(f"{MAGENTA}{BOLD}🔗 {tag}{RESET} {content}")
    except Exception as e:
        print(f"{RED}Logcat stream error: {e}{RESET}")
    finally:
        proc.terminate()


def getevent_thread(device_path, max_x, max_y, screen_w, screen_h):
    """Reads adb getevent and prints formatted TAP events mapped to pixels."""
    print(f"{BLUE}info: Launching Touch Input listener on {device_path}...{RESET}")

    proc = subprocess.Popen(
        ["adb", "shell", "getevent", "-lt", device_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    if proc.stdout is None:
        print(f"{RED}Error: Failed to open getevent stdout stream.{RESET}")
        return

    # regex matches EV_ABS ABS_MT_TRACKING_ID 00001ab3
    # format: [   75432.123456] EV_ABS             ABS_MT_TRACKING_ID   00001ab3
    event_re = re.compile(
        r"(?:\[\s*\d+\.\d+\]\s+)?([A-Z0-9_]+)\s+([A-Z0-9_]+)\s+([0-9a-fA-F]+)"
    )

    touches = {}
    current_slot = 0

    try:
        for line in iter(proc.stdout.readline, ""):
            match = event_re.search(line)
            if not match:
                continue

            ev_type, ev_code, ev_val = match.groups()

            if ev_code == "ABS_MT_SLOT":
                current_slot = int(ev_val, 16)
            elif ev_code == "ABS_MT_TRACKING_ID":
                val_dec = int(ev_val, 16)
                if val_dec != 0xFFFFFFFF:  # Touch down
                    touches[current_slot] = {"x": None, "y": None}
                else:  # Touch up
                    touch = touches.pop(current_slot, None)
                    if touch and touch["x"] is not None and touch["y"] is not None:
                        x_raw = int(touch["x"], 16)
                        y_raw = int(touch["y"], 16)

                        # Map to screen dimensions
                        px_x = int((x_raw / max_x) * screen_w)
                        px_y = int((y_raw / max_y) * screen_h)

                        # Constrain to screen bounds
                        px_x = max(0, min(px_x, screen_w))
                        px_y = max(0, min(px_y, screen_h))

                        pct_x = (px_x / screen_w) * 100
                        pct_y = (px_y / screen_h) * 100

                        print(
                            f"{YELLOW}{BOLD}👉 [TAP] Screen Touch Up at X: {px_x:<4} ({pct_x:.1f}%), Y: {px_y:<4} ({pct_y:.1f}%){RESET}"
                        )
            elif ev_code == "ABS_MT_POSITION_X":
                if current_slot in touches:
                    touches[current_slot]["x"] = ev_val
            elif ev_code == "ABS_MT_POSITION_Y":
                if current_slot in touches:
                    touches[current_slot]["y"] = ev_val
    except Exception as e:
        print(f"{RED}Touch listener error: {e}{RESET}")
    finally:
        proc.terminate()


def main():
    print(f"{BOLD}{BLUE}===================================================={RESET}")
    print(f"{BOLD}{BLUE}        OMNIPLAY REAL-TIME LOGGING SERVICE          {RESET}")
    print(f"{BOLD}{BLUE}===================================================={RESET}")

    # 1. Screen size
    w, h = get_screen_size()
    print(f"{BLUE}Device Resolution:{RESET} {w}x{h}")

    # 2. Touch event device
    dev, max_x, max_y = find_touchscreen_device()
    if not dev:
        print(f"{RED}Aborting: No touchscreen device found or ADB disconnected.{RESET}")
        return
    print(
        f"{BLUE}Touchscreen Device:{RESET} {dev} (Max Coordinate range: {max_x}x{max_y})"
    )

    # 3. Launch threads
    t_logcat = threading.Thread(target=logcat_thread, daemon=True)
    t_getevent = threading.Thread(
        target=getevent_thread, args=(dev, max_x, max_y, w, h), daemon=True
    )

    t_logcat.start()
    t_getevent.start()

    print(f"{GREEN}{BOLD}Running! Press Ctrl+C to stop.{RESET}")
    print(f"{BOLD}Logging TAP events and API network requests now...{RESET}")
    print(f"----------------------------------------------------\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print(f"\n{BLUE}Exiting Logging Service. Have a great day!{RESET}")


if __name__ == "__main__":
    main()
