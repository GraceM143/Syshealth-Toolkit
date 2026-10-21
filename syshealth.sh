#!/usr/bin/env bash
# ===============================================
# syshealth.sh - System Health & Log Analysis Toolkit
# Lab 5
# Author: Grace McGinn
# Date: $(10/20/2026 +%Y-%m-%d)
# ==============================================
set -euo pipefall

# Trap for logging on error or unespected event
trap 'log_message "ERROR" "Script exited unexpectedly with code $?"' ERR
trap 'log_message "INFO" "Script finished normally with code $?"' EXIT

# --- Thresholds (change these values to test alert behavior --- 
CPU_THRESHOLD=75
MEM_THRESHOLD=85
DISK_THRESHOLD=85

# --- Function definiitions will go here (print_status, check_*, run_*, parse_*, generate_*) ---
print_status() {
	local status="$1"
       	local message="$2"
       	if [ "$status" = "OK" ]; then
                echo -e "\e[32m OK: $message\e[0m"
       	else
               echo -e "\e[31m ALERT: $message\e[0m"
       	fi
}

check_disk_usage() {
	local mount="$1"
	local pct threshold
	threshold="$DISK_THRESHOLD"

	if [ ! mountpoint -q "$mount" 2>/dev/null ] && [ "$mount" != "/" ]; then
		print_status "OK" "Mount point $mount does not exist on this system"
		return 0
	fi

	pct=$(df "$mount" | tail -1 | awk '{gsub("%",""); print $5}')

	if (( pct > threshold )); then
		print_status "ALERT" "Disk usage on $mount is ${pct}% (threshold ${threshold}%)"
		return 1
	else
		print_status "OK" "Disk usage is $mount is ${pct}%"
		return 0
	fi
}

check_memory_usage() {
	local pct threshold
	threshold="$MEM_THRESHOLD"
	pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')

	if (( pct > threshold )); then
		print_status "ALERT" "Memory usage is ${pct}% (threshold ${threshold}%)"
		return 1
	else
		print_status "OK" "Memory usage is ${pct}%"
		return 0
	fi
}	

check_cpu_usage() {
	local pct threshold
	threshold="$CPU_THRESHOLD"
	pct=$(top -bn1 | grep '^%Cpu' | awk '{print 100 - $8}' | cut -d. -f1)

	if (( pct > threshold )); then
		print_status "ALERT" "CPU usage is ${pct}% (threshold ${threshold}%)"
		return 1
	else
		print_status "OK" "CPU usage is ${pct}%"
		return 0
	fi
}

run_health_checks() {
	local overall_status=0

	print_status "CHECK" "Running system health analysis..."

	# DIsk checks via loop (replaces the inline for-loop from Lab 2)
	for mount in / /home /var; do
		if ! check_disk_usage "$mount"; then
			overall_status=1
		fi
	done

	#Memory check
	if ! check_memory_usage; then
		overall_status=1
	fi
	
	# CPU check
	if ! check_cpu_usage; then
		overall_status=1
	fi

	# Store result for generate_report / exit
	HEALTH_STATUS="$overall_status"
	return "$overall_status"
}

analyze_logs() {
	local log_file="${1:-/var/log/messages}" #default to rocky linux 9 main log
	local errors=0
	local warnings=0
	local failed_logins=0
	local top_issues

	#graceful handling if log file is missing or unreadable
        if [ ! -r "$log_file" ]; then
                printf "\nLog Analysis Summary (%s):\n" "$(basename "$log_file")"
                printf " Log file is not readable or does not exist on this system.\n"
                printf " (This is normal in some containers or minimal installs.)\n"
		return 0
	fi

	#count issues using extended regex (case-insensitive where useful)
	errors=$(grep -E -i 'ERROR|Error|error' "$log_file" 2>/dev/null | wc -l)
	warnings=$(grep -E -i 'WARNING|Warning|warning' "$log_file" 2>/dev/null | wc -l)
	failed_logins=$(grep -E -i 'Failed password|authentication failure|Failed login' "$log_file" 2>/dev/null | wc -l)

	#Top 5 most common errors/warning messages (cleaned with sed)
        printf "\nTop 5 recurring issues:\n"
        grep -E -i 'ERROR|Error|error|WARNING|Warning|warning|Failed password|authentication failure' "$log_file" 2>/dev/null \
                | sed 's/.*\]: //' \
                | sort \
		| uniq -c \
                | sort -nr \
                | head -5 \

        #summary section
        printf "\nLog Analysis Summary (%s):\n" "$(basename "$log_file")"
        printf "  Errors        : %d\n" "$errors"
        printf "  Warnings      : %d\n" "$warnings"
        printf "  Failed logins : %d\n" "$failed_logins"
}

parse_arguments() {
	OUTPUT_FILE="${1:-}" #if $1 is given, use it as output file; otherwise empty
}

generate_report(){
	#Re-collect the human-readable metrics (same as lab 1)
	local CURRENT_DATE HOSTNAME UPTIME DISK_USAGE MEMORY_USAGE PROCESS_COUNT
	
	HOSTNAME=$(hostname)
	CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
	UPTIME=$(uptime -p)
	DISK_USAGE=$(df -h / | tail -1)
	MEMORY_USAGE=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
	PROCESS_COUNT=$(ps -e | wc -l)

	printf "==========================================\n"
	printf "System Health Report -%s\n" "$CURRENT_DATE"
	printf "Hostname	: %s\n" "$HOSTNAME"
	printf "Uptime		: %s\n" "$UPTIME"
	printf "Disk /		: %s\n" "$DISK_USAGE"
	printf "Memory used	: %s\n" "$MEMORY_USAGE"
	printf "Total processes	: %s\n" "$PROCESS_COUNT"
	printf "Health status	: %s\n" "$([ "$HEALTH_STATUS" -eq 0 ] && echo "HEALTHY" || echo "UNHEALTHY - see alerts above")"
	printf "=========================================\n"
	
	#--- NEW: log analysis summary (integrated into every report ---
	printf "\n=========+===============================\n"
	printf "LOG ANALYSIS SUMMARY\n"
	printf "=========================================\n"
	analyze_logs # uses default /var/log/messages
}

main() {
        parse_arguments "$@"
        #Run all health checks (prints colored alerts to terminal)
        run_health_checks

        #Generate the structure report (to screen or file)
        if [ -n "$OUTPUT_FILE" ]; then
                generate_report > "$OUTPUT_FILE"
                echo "Report written to $OUTPUT_FILE"
       	else
                generate_report
        fi

        #Exit with the aggregated health status from run_health_status
        exit "${HEALTH_STATUS:-0}"
}

# --- the single call that starts everything - must be the last line
main
