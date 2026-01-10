#!/bin/bash

#===============================================================================
# CrowsNest NUT Notification Handler
#===============================================================================
#
# This script is invoked by upsmon, the UPS monitoring and shutdown
# controller which is a component of Network UPS Toolkit (NUT).
#
# upsmon provides a customisable NOTIFYCMD directive, allowing custom
# notification scripts to run based on UPS power events.
#
# This script simply parses NUT notification types and outputs
# to both stdout and a log file.
#
# upsmon sets the NOTIFYTYPE environment variable and passes the
# notification message as an argument.
#
# NUT Notification Types:
#   ONLINE    - UPS is back on line power
#   ONBATT    - UPS is running on battery
#   LOWBATT   - UPS battery is low (shutdown imminent)
#   FSD       - Forced shutdown in progress
#   COMMOK    - Communications with UPS established
#   COMMBAD   - Communications with UPS lost
#   SHUTDOWN  - System is being shutdown
#   REPLBATT  - UPS battery needs replacement
#   NOCOMM    - UPS is unavailable (not responding)
#   NOPARENT  - upsmon parent process died (loss of communications)
#
# Usage: crowsnest_notifycmd.sh <notification_message>
#
# Environment Variables:
#   NOTIFYTYPE  - Set by upsmon to indicate the notification type
#   UPSNAME     - (Optional) Name of the UPS that triggered the event
#
#===============================================================================

set -o pipefail

# Configuration
# Host filesystem mount point (standard for privileged containers)
HOST_ROOT="${HOST_ROOT:-/host}"

# Log file (on the host filesystem for persistence)
LOG_FILE="${HOST_ROOT}/var/log/crowsnest-notify.log"

# Colors for terminal output (only if stdout is a TTY)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    NC=''
fi

#-------------------------------------------------------------------------------
# Logging functions
#-------------------------------------------------------------------------------

# Log to both stdout and host log file
log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Format for log file (no colors)
    local log_entry="[$timestamp] [$level] $message"

    # Format for stdout (with colors if available)
    local stdout_entry="${color}[$timestamp]${NC} ${color}[$level]${NC} $message"

    # Output to stdout
    echo -e "$stdout_entry"

    # Output to host log file
    echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
    log "INFO" "$GREEN" "$1"
}

log_warn() {
    log "WARN" "$YELLOW" "$1"
}

log_error() {
    log "ERROR" "$RED" "$1"
}

log_critical() {
    log "CRITICAL" "$MAGENTA" "$1"
}

log_debug() {
    log "DEBUG" "$CYAN" "$1"
}

#-------------------------------------------------------------------------------
# Notification type handlers
#-------------------------------------------------------------------------------

# Get severity and description for notification type
get_notification_info() {
    local notify_type="$1"

    case "$notify_type" in
        ONLINE)
            echo "INFO|Power restored - UPS is back on line power"
            ;;
        ONBATT)
            echo "WARN|Power failure - UPS is running on battery"
            ;;
        LOWBATT)
            echo "CRITICAL|Low battery - UPS battery is critically low, shutdown imminent"
            ;;
        FSD)
            echo "CRITICAL|Forced shutdown - UPS is forcing system shutdown"
            ;;
        COMMOK)
            echo "INFO|Communications OK - Connection to UPS established"
            ;;
        COMMBAD)
            echo "WARN|Communications lost - Connection to UPS failed"
            ;;
        SHUTDOWN)
            echo "CRITICAL|Shutdown - System is shutting down now"
            ;;
        REPLBATT)
            echo "WARN|Replace battery - UPS battery needs replacement"
            ;;
        NOCOMM)
            echo "ERROR|No communication - UPS is not responding"
            ;;
        NOPARENT)
            echo "ERROR|No parent - upsmon parent process died unexpectedly"
            ;;
        CAL)
            echo "INFO|Calibration - UPS is performing battery calibration"
            ;;
        NOTCAL)
            echo "INFO|Calibration complete - UPS calibration finished"
            ;;
        OFF)
            echo "WARN|UPS offline - UPS is off or unavailable"
            ;;
        NOTOFF)
            echo "INFO|UPS online - UPS is back online"
            ;;
        BYPASS)
            echo "WARN|Bypass mode - UPS is in bypass mode"
            ;;
        NOTBYPASS)
            echo "INFO|Normal mode - UPS returned from bypass mode"
            ;;
        *)
            echo "INFO|Unknown notification type: $notify_type"
            ;;
    esac
}

# Handle specific notification types with custom actions
handle_notification() {
    local notify_type="$1"
    local message="$2"

    case "$notify_type" in
        ONLINE)
            log_info "⚡ POWER RESTORED: $message"
            log_info "UPS is back on line power - normal operation resumed"
            ;;
        ONBATT)
            log_warn "🔋 ON BATTERY: $message"
            log_warn "Power failure detected - running on UPS battery"
            log_warn "Monitor battery level - shutdown will occur if power is not restored"
            ;;
        LOWBATT)
            log_critical "⚠️  LOW BATTERY: $message"
            log_critical "UPS battery critically low - system shutdown is imminent!"
            log_critical "Save all work immediately - power will be lost soon"
            ;;
        FSD)
            log_critical "🛑 FORCED SHUTDOWN: $message"
            log_critical "UPS has initiated forced shutdown sequence"
            log_critical "System will power off momentarily"
            ;;
        COMMOK)
            log_info "✅ COMMUNICATIONS OK: $message"
            log_info "Successfully connected to UPS monitoring daemon"
            ;;
        COMMBAD)
            log_warn "❌ COMMUNICATIONS LOST: $message"
            log_warn "Lost connection to UPS - monitoring may be impaired"
            log_warn "Check network connectivity and UPS daemon status"
            ;;
        SHUTDOWN)
            log_critical "💀 SHUTDOWN IN PROGRESS: $message"
            log_critical "System shutdown has been initiated"
            ;;
        REPLBATT)
            log_warn "🔧 BATTERY REPLACEMENT NEEDED: $message"
            log_warn "UPS battery is failing and should be replaced"
            log_warn "Schedule battery replacement to maintain power protection"
            ;;
        NOCOMM)
            log_error "📡 NO COMMUNICATION: $message"
            log_error "UPS is not responding to status queries"
            log_error "Check UPS power and connectivity"
            ;;
        NOPARENT)
            log_error "👻 PARENT PROCESS DIED: $message"
            log_error "upsmon parent process has terminated unexpectedly"
            log_error "This may indicate a serious problem - check system logs"
            ;;
        CAL)
            log_info "📊 CALIBRATION: $message"
            log_info "UPS is performing battery runtime calibration"
            ;;
        NOTCAL)
            log_info "📊 CALIBRATION COMPLETE: $message"
            ;;
        OFF)
            log_warn "⭕ UPS OFFLINE: $message"
            ;;
        NOTOFF)
            log_info "🟢 UPS ONLINE: $message"
            ;;
        BYPASS)
            log_warn "⚡ BYPASS MODE: $message"
            log_warn "UPS is in bypass mode - no battery protection active"
            ;;
        NOTBYPASS)
            log_info "🔒 NORMAL MODE: $message"
            log_info "UPS returned to normal operation from bypass"
            ;;
        *)
            log_info "📢 NOTIFICATION [$notify_type]: $message"
            ;;
    esac
}

# Print a summary header
print_header() {
    local notify_type="$1"
    local ups_name="${UPSNAME:-unknown}"

    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  CrowsNest UPS Notification${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${CYAN}Type:${NC}      $notify_type"
    echo -e "  ${CYAN}UPS:${NC}       $ups_name"
    echo -e "  ${CYAN}Time:${NC}      $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo -e "${WHITE}────────────────────────────────────────────────────────────${NC}"
}

#-------------------------------------------------------------------------------
# Main function
#-------------------------------------------------------------------------------

main() {
    # Get notification type from environment (set by upsmon)
    local notify_type="${NOTIFYTYPE:-UNKNOWN}"

    # Get notification message from arguments
    local message="${*:-No message provided}"

    # Check if host filesystem is mounted (for logging)
    if [[ ! -d "$HOST_ROOT" ]]; then
        echo "[WARN] Host filesystem not mounted at $HOST_ROOT - logging to stdout only"
        LOG_FILE="/dev/null"
    fi

    # Print header
    print_header "$notify_type"

    # Log raw notification data for debugging
    log_debug "NOTIFYTYPE=$notify_type"
    log_debug "Message: $message"
    log_debug "UPSNAME=${UPSNAME:-not set}"

    # Handle the notification
    handle_notification "$notify_type" "$message"

    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Return appropriate exit code based on severity
    case "$notify_type" in
        LOWBATT|FSD|SHUTDOWN)
            exit 2  # Critical
            ;;
        COMMBAD|NOCOMM|NOPARENT|ONBATT)
            exit 1  # Warning/Error
            ;;
        *)
            exit 0  # Info/OK
            ;;
    esac
}

# Run main function with all arguments
main "$@"

