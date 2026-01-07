#!/bin/bash

# Network Monitor Control Script
# Helper script to start, stop, and check status of network-monitor.sh

SCRIPT_NAME="network-monitor.sh"
LOG_FILE="monitor.log"

show_usage() {
    echo "Network Monitor Control"
    echo "Usage: $0 {start|stop|status|logs|restart} [monitor_args...]"
    echo ""
    echo "Commands:"
    echo "  start <args>  - Start monitoring in background"
    echo "  stop          - Stop all running monitors"
    echo "  status        - Show running monitor processes"
    echo "  logs          - Show recent log output"
    echo "  restart <args>- Stop and restart with new arguments"
    echo ""
    echo "Examples:"
    echo "  $0 start 8.8.8.8 1.1.1.1 208.67.222.222"
    echo "  $0 stop"
    echo "  $0 status"
    echo "  $0 logs"
}

start_monitor() {
    if [ $# -lt 1 ]; then
        echo "Error: No monitoring arguments provided"
        echo "Usage: $0 start <test_ip> <diagnostic_ip1> [diagnostic_ip2] ..."
        exit 1
    fi
    
    # Check if already running
    if pgrep -f "$SCRIPT_NAME" > /dev/null; then
        echo "Network monitor is already running. Stop it first with: $0 stop"
        exit 1
    fi
    
    echo "Starting network monitor with arguments: $*"
    echo "Logs will be written to: $LOG_FILE"
    
    nohup ./"$SCRIPT_NAME" "$@" > "$LOG_FILE" 2>&1 &
    local pid=$!
    
    sleep 2
    if ps -p $pid > /dev/null; then
        echo "Network monitor started successfully (PID: $pid)"
        echo "Use '$0 status' to check status or '$0 logs' to view output"
    else
        echo "Failed to start network monitor. Check $LOG_FILE for errors."
        exit 1
    fi
}

stop_monitor() {
    local pids=$(pgrep -f "$SCRIPT_NAME")
    
    if [ -z "$pids" ]; then
        echo "No network monitor processes found running"
        return 0
    fi
    
    echo "Stopping network monitor processes..."
    pkill -TERM -f "$SCRIPT_NAME"
    
    # Wait a moment for graceful shutdown
    sleep 3
    
    # Check if still running and force kill if necessary
    if pgrep -f "$SCRIPT_NAME" > /dev/null; then
        echo "Processes still running, forcing termination..."
        pkill -KILL -f "$SCRIPT_NAME"
        sleep 1
    fi
    
    if pgrep -f "$SCRIPT_NAME" > /dev/null; then
        echo "Error: Unable to stop all processes"
        exit 1
    else
        echo "Network monitor stopped successfully"
    fi
}

show_status() {
    local pids=$(pgrep -f "$SCRIPT_NAME")
    
    if [ -z "$pids" ]; then
        echo "Network monitor: NOT RUNNING"
    else
        echo "Network monitor: RUNNING"
        echo ""
        echo "Process details:"
        ps -f -p $pids 2>/dev/null || echo "Error getting process details"
        echo ""
        echo "Command line:"
        ps -o pid,cmd -p $pids --no-headers 2>/dev/null
    fi
}

show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found: $LOG_FILE"
        exit 1
    fi
    
    echo "Recent network monitor logs (last 50 lines):"
    echo "=============================================="
    tail -50 "$LOG_FILE"
    echo ""
    echo "To follow logs in real-time: tail -f $LOG_FILE"
}

restart_monitor() {
    echo "Restarting network monitor..."
    stop_monitor
    sleep 2
    start_monitor "$@"
}

case "$1" in
    start)
        shift
        start_monitor "$@"
        ;;
    stop)
        stop_monitor
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    restart)
        shift
        restart_monitor "$@"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac