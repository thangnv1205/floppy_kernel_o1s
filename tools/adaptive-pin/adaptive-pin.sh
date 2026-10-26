#!/system/bin/sh
# Adaptive frequency pinning for Exynos 2100.
# Clamps cpufreq policy (CPU clusters, DVFS via ACPM) and Mali devfreq (GPU)
# between two profiles: "battery" (deep-sleep friendly) and "game" (max perf).
# Available OPPs are read from sysfs at runtime; nothing is hardcoded because
# the frequency tables live in ACPM firmware.
#
# Usage: adaptive-pin.sh apply battery|game | reset | daemon | test <pkg>

CONF=${ADAPTIVE_PIN_CONF:-/data/adaptive-pin.conf}

log() {
    echo "adaptive-pin: $*" > /dev/kmsg 2>/dev/null
}

# cfg KEY DEFAULT
cfg() {
    val=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -n1)
    [ -n "$val" ] || val="$2"
    echo "$val"
}

# sorted_avail FILE -> frequencies, ascending, space separated
sorted_avail() {
    cat "$1" 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | tr '\n' ' '
}

# pick_freq "ascending freqs" PERCENT -> OPP at pct of the range, 1..100
pick_freq() {
    # POSIX: a leading comment line in a function body comments out the
    # first command, so keep a real statement first.
    pct=$2
    set -- $1
    count=$#
    [ "$count" -gt 0 ] || return 1
    pos=$(( (2 * (count - 1) * pct + 100) / 200 ))
    i=0
    while [ "$i" -lt "$pos" ]; do shift; i=$((i + 1)); done
    echo "$1"
}

cluster_apply() {  # cluster_apply MODE POLICY_DIR AVAIL "min max"
    mode=$1 dir=$2 avail=$3
    set -- $avail
    lo=$1
    hi=$*
    hi=${hi##* }
    case $mode in
        battery)
            echo "$lo" > "$dir/scaling_min_freq"
            echo "$(pick_freq "$avail" "$(cfg BATTERY_CPU_MAX_PERCENT 65)")" > "$dir/scaling_max_freq"
            ;;
        game)
            echo "$hi" > "$dir/scaling_max_freq"
            pct=$(cfg GAME_CPU_MIN_PERCENT 100)
            if [ "$pct" -ge 100 ]; then
                echo "$hi" > "$dir/scaling_min_freq"
            else
                echo "$(pick_freq "$avail" "$pct")" > "$dir/scaling_min_freq"
            fi
            ;;
        reset)
            echo "$lo" > "$dir/scaling_min_freq"
            echo "$hi" > "$dir/scaling_max_freq"
            ;;
    esac
    log "${dir##*/} $mode -> $(cat "$dir/scaling_min_freq" 2>/dev/null)/$(cat "$dir/scaling_max_freq" 2>/dev/null)"
}

cpu_apply() {  # cpu_apply MODE
    for dir in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$dir" ] || continue
        avail=$(sorted_avail "$dir/scaling_available_frequencies")
        [ -n "$avail" ] || continue
        cluster_apply "$1" "$dir" "$avail"
    done
}

gpu_apply() {  # gpu_apply MODE
    mode=$1
    for dir in /sys/class/devfreq/*; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        case $name in
            *mali*|*gpu*|*G3D*) ;;
            *) continue ;;
        esac
        avail=$(sorted_avail "$dir/available_frequencies")
        [ -n "$avail" ] || continue
        set -- $avail
        lo=$1
        all="$*"
        hi=${all##* }
        case $mode in
            battery)
                echo "$(pick_freq "$avail" "$(cfg BATTERY_GPU_MAX_PERCENT 55)")" > "$dir/max_freq"
                echo "$lo" > "$dir/min_freq"
                ;;
            game)
                echo "$hi" > "$dir/max_freq"
                pct=$(cfg GAME_GPU_MIN_PERCENT 70)
                if [ "$pct" -ge 100 ]; then
                    echo "$hi" > "$dir/min_freq"
                else
                    echo "$(pick_freq "$avail" "$pct")" > "$dir/min_freq"
                fi
                if [ "$(cfg GAME_GPU_PERFORMANCE_GOV 0)" = 1 ]; then
                    echo performance > "$dir/governor" 2>/dev/null
                fi
                ;;
            reset)
                echo "$lo" > "$dir/min_freq"
                echo "$hi" > "$dir/max_freq"
                echo "$(cfg GPU_DEFAULT_GOVERNOR simpleondemand)" > "$dir/governor" 2>/dev/null
                ;;
        esac
        log "gpu $name $mode"
    done
}

apply_profile() {
    cpu_apply "$1"
    gpu_apply "$1"
}

device_awake() {
    dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'
}

current_foreground() {
    dumpsys window displays 2>/dev/null |
        grep -m1 -e mCurrentFocus -e mFocusedApp |
        grep -o '[A-Za-z0-9._+~-]*/[A-Za-z0-9._+~$-]*' |
        head -n1 |
        cut -d/ -f1
}

is_game_pkg() {
    for p in $(cfg GAME_PACKAGES ""); do
        [ "$p" = "$1" ] && return 0
    done
    return 1
}

daemon() {
    interval=$(cfg DETECT_INTERVAL_SEC 2)
    marker=$(cfg GAME_MARKER_FILE /data/adaptive-pin.game)
    mode=""
    while :; do
        new=battery
        if device_awake; then
            if [ -n "$marker" ] && [ -f "$marker" ]; then
                new=game
            elif [ "$(cfg DETECT_MODE marker)" = foreground ]; then
                pkg=$(current_foreground)
                [ -n "$pkg" ] && is_game_pkg "$pkg" && new=game
            fi
        fi
        if [ "$new" != "$mode" ]; then
            apply_profile "$new"
            mode=$new
            log "profile=$new"
        fi
        sleep "$interval"
    done
}

case $1 in
    apply)
        apply_profile "$2"
        ;;
    reset)
        cpu_apply reset
        gpu_apply reset
        ;;
    test)
        if is_game_pkg "$2"; then echo game; else echo battery; fi
        ;;
    daemon|"")
        daemon
        ;;
    *)
        echo "usage: adaptive-pin.sh apply battery|game | reset | daemon | test <pkg>" >&2
        exit 1
        ;;
esac
