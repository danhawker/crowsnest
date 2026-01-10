#!/bin/bash

#===============================================================================
# CrowsNest Node Shutdown Script
#===============================================================================
#
# This script is invoked by upsmon, the UPS monitoring and shutdown
# controller which is a component of Network UPS Toolkit (NUT).
#
# upsmon provides a customisable SHUTDOWNCMD parameter, allowing custom
# scripts to enable complex systems to be safely shutdown before power failure.
#
# This script attempts to safely shutdown the local OpenShift node using
# standard OpenShift tools to mark the node unschedulable, initiate the drain
# process, and finally invoke a systemd poweroff.
#
# Note: This script is designed to run from within a suitably privileged 
# pod/container with access to the host filesystem and systemd.
#
#===============================================================================

set -o pipefail

# Configuration
# Host filesystem mount point (standard for privileged containers)
HOST_ROOT="${HOST_ROOT:-/host}"

# Kubeconfig location on the node (paths are relative to host root)
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig}"

# Alternative kubeconfigs to try if the primary fails
KUBECONFIG_ALTERNATIVES=(
    "/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig"
    "/var/lib/kubelet/kubeconfig"
)

# oc binary location (relative to host root)
OC_BIN="${OC_BIN:-/usr/bin/oc}"

# Timeout for cordon operation (seconds)
CORDON_TIMEOUT="${CORDON_TIMEOUT:-10}"

# Timeout for drain operation (seconds)
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-20}"

# Timeout for each shutdown method (seconds)
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-10}"

# Log file (on the host filesystem for persistence)
LOG_FILE="${HOST_ROOT}/var/log/crowsnest-shutdown.log"

#-------------------------------------------------------------------------------
# Logging functions
#-------------------------------------------------------------------------------

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    log "ERROR: $1"
}

log_info() {
    log "INFO: $1"
}

#-------------------------------------------------------------------------------
# Utility functions
#-------------------------------------------------------------------------------

# Check that the host filesystem is mounted
check_host_mount() {
    if [[ ! -d "$HOST_ROOT" ]]; then
        log_error "Host filesystem not mounted at $HOST_ROOT"
        return 1
    fi

    if [[ ! -d "${HOST_ROOT}/usr" ]]; then
        log_error "Host filesystem appears invalid (no /usr directory)"
        return 1
    fi

    log_info "Host filesystem mounted at: $HOST_ROOT"
    return 0
}

# Verify oc binary exists on host
check_oc() {
    if [[ ! -x "${HOST_ROOT}${OC_BIN}" ]]; then
        log_error "oc binary not found at ${HOST_ROOT}${OC_BIN}"
        return 1
    fi

    log_info "Found oc binary: $OC_BIN"
    return 0
}

# Find a working kubeconfig on the host
find_kubeconfig() {
    # Check if configured kubeconfig exists on host
    if [[ -f "${HOST_ROOT}${KUBECONFIG}" ]]; then
        log_info "Using kubeconfig: $KUBECONFIG"
        return 0
    fi

    # Try alternatives
    for alt in "${KUBECONFIG_ALTERNATIVES[@]}"; do
        if [[ -f "${HOST_ROOT}${alt}" ]]; then
            KUBECONFIG="$alt"
            log_info "Using alternative kubeconfig: $KUBECONFIG"
            return 0
        fi
    done

    log_error "Could not find a valid kubeconfig"
    return 1
}

# Get the current node name
get_node_name() {
    # Try to get node name from environment (set by downward API)
    if [[ -n "${NODE_NAME:-}" ]]; then
        echo "$NODE_NAME"
        return 0
    fi

    # Try to get from host's hostname file
    local hostname
    hostname=$(cat "${HOST_ROOT}/etc/hostname" 2>/dev/null)

    if [[ -n "$hostname" ]]; then
        echo "$hostname"
        return 0
    fi

    # Fallback to container hostname (may not match node name)
    hostname=$(hostname 2>/dev/null)
    if [[ -n "$hostname" ]]; then
        log_info "Using container hostname (may not match node): $hostname"
        echo "$hostname"
        return 0
    fi

    log_error "Could not determine node name"
    return 1
}

# Run oc command via chroot into host filesystem
oc_cmd() {
    chroot "$HOST_ROOT" "$OC_BIN" --kubeconfig="$KUBECONFIG" "$@"
}

#-------------------------------------------------------------------------------
# Shutdown functions
#-------------------------------------------------------------------------------

cordon_node() {
    local node="$1"
    log_info "Cordoning node: $node (timeout: ${CORDON_TIMEOUT}s)"

    if timeout "${CORDON_TIMEOUT}" chroot "$HOST_ROOT" "$OC_BIN" --kubeconfig="$KUBECONFIG" adm cordon "$node"; then
        log_info "Node $node cordoned successfully"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Cordon timed out after ${CORDON_TIMEOUT}s - continuing anyway"
        else
            log_error "Failed to cordon node: $node (exit code: $exit_code)"
        fi
        return 1
    fi
}

drain_node() {
    local node="$1"
    log_info "Draining node: $node (timeout: ${DRAIN_TIMEOUT}s)"

    # Drain with appropriate flags for emergency shutdown
    # Use timeout command to enforce hard limit, oc drain timeout as soft limit
    if timeout "${DRAIN_TIMEOUT}" chroot "$HOST_ROOT" "$OC_BIN" --kubeconfig="$KUBECONFIG" \
        adm drain "$node" \
        --delete-emptydir-data \
        --ignore-daemonsets=true \
        --timeout="${DRAIN_TIMEOUT}s" \
        --force \
        --grace-period=5; then
        log_info "Node $node drained successfully"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Drain timed out after ${DRAIN_TIMEOUT}s - continuing with shutdown anyway"
        else
            log_error "Failed to drain node: $node (exit code: $exit_code) - continuing with shutdown anyway"
        fi
        return 1
    fi
}

shutdown_host() {
    log_info "Initiating host shutdown..."

    # Try multiple methods to shutdown the host

    # Method 1: Use systemctl via chroot (preferred)
    if [[ -S "${HOST_ROOT}/run/systemd/private" ]] || [[ -S "${HOST_ROOT}/run/dbus/system_bus_socket" ]]; then
        log_info "Attempting systemctl poweroff via chroot (timeout: ${SHUTDOWN_TIMEOUT}s)..."
        if timeout "${SHUTDOWN_TIMEOUT}" chroot "$HOST_ROOT" /usr/bin/systemctl poweroff; then
            return 0
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                log_error "systemctl poweroff timed out - trying next method"
            else
                log_error "systemctl poweroff failed (exit code: $exit_code) - trying next method"
            fi
        fi
    fi

    # Method 2: Direct shutdown command via chroot
    log_info "Attempting shutdown command via chroot (timeout: ${SHUTDOWN_TIMEOUT}s)..."
    if timeout "${SHUTDOWN_TIMEOUT}" chroot "$HOST_ROOT" /sbin/shutdown -h now; then
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "shutdown command timed out - trying next method"
        else
            log_error "shutdown command failed (exit code: $exit_code) - trying next method"
        fi
    fi

    # Method 3: Echo to sysrq (last resort - emergency shutdown)
    log_info "Attempting emergency shutdown via sysrq (timeout: ${SHUTDOWN_TIMEOUT}s)..."
    if [[ -f "${HOST_ROOT}/proc/sysrq-trigger" ]]; then
        # Run sysrq sequence with timeout wrapper
        if timeout "${SHUTDOWN_TIMEOUT}" bash -c "
            # Sync filesystems
            echo s > '${HOST_ROOT}/proc/sysrq-trigger'
            sleep 1
            # Unmount filesystems
            echo u > '${HOST_ROOT}/proc/sysrq-trigger'
            sleep 1
            # Power off
            echo o > '${HOST_ROOT}/proc/sysrq-trigger'
        "; then
            return 0
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                log_error "sysrq shutdown timed out"
            else
                log_error "sysrq shutdown failed (exit code: $exit_code)"
            fi
        fi
    fi

    log_error "All shutdown methods failed!"
    return 1
}

#-------------------------------------------------------------------------------
# Main function
#-------------------------------------------------------------------------------

main() {
    log_info "=========================================="
    log_info "CrowsNest Shutdown Script Started"
    log_info "=========================================="
    log_info "Triggered by UPS power event"

    # Verify host filesystem is mounted
    if ! check_host_mount; then
        log_error "Host filesystem not available - cannot proceed"
        exit 1
    fi

    # Check oc binary exists on host
    if ! check_oc; then
        log_error "Cannot find oc binary - attempting direct shutdown"
        shutdown_host
        exit 1
    fi

    # Find kubeconfig on host
    if ! find_kubeconfig; then
        log_error "Cannot find kubeconfig - attempting direct shutdown"
        shutdown_host
        exit 1
    fi

    # Get node name
    local node_name
    if ! node_name=$(get_node_name); then
        log_error "Cannot determine node name - attempting direct shutdown"
        shutdown_host
        exit 1
    fi

    log_info "Node name: $node_name"

    # Step 1: Cordon the node (mark unschedulable)
    # This prevents new pods from being scheduled on this node
    cordon_node "$node_name" || true

    # Step 2: Drain the node (evict pods)
    # Best effort - we don't want to delay shutdown if drain fails
    drain_node "$node_name" || true

    # Step 3: Shutdown the host
    # This triggers the Kubelet's graceful node shutdown if configured
    log_info "Proceeding with host shutdown..."
    shutdown_host

    # If we get here, something went wrong with shutdown
    log_error "Shutdown command returned - this should not happen"
    exit 1
}

# Run main function
main "$@"
