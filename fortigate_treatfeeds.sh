#!/bin/bash

# Configuration
config_file="/opt/ff/feeds.conf"
log_file="/opt/ff/script.log"
output_dir="/opt/ff"
max_lines=131000
parallel_downloads=4  # Number of parallel downloads

# Create the directories if they don't exist
mkdir -p /opt/ff/cache

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$log_file"
}

# Export the log function so it can be used in subshells
export -f log
export log_file

# Cleanup function to remove cache files on script exit
cleanup() {
    rm -rf /opt/ff/cache/*
    log "Cache cleanup completed."
}

# Trap to ensure cleanup happens on script exit
trap cleanup EXIT

# Function to download a single URL
download_url() {
    local url="$1"
    local temp_download="/opt/ff/cache/$(basename "$url")"
    log "Downloading $url to $temp_download"
    if curl --max-time 280 -f -o "$temp_download" "$url"; then
        log "Successfully downloaded $url"
        if [[ -s "$temp_download" ]]; then
            file_size=$(stat -c%s "$temp_download")
            log "Downloaded file size: $file_size bytes"
            echo "$temp_download"
        else
            log "Downloaded file $temp_download is empty"
        fi
    else
        log "Failed to download $url (HTTP error or timeout)"
    fi
}

# Export the download_url function so it can be used in subshells
export -f download_url

# Process each section in the configuration file
process_section() {
    local section="$1"
    local output_file_base="$2"
    local temp_file="/opt/ff/cache/temp_${section,,}.txt"  # Unique temp file for each section
    
    log "Processing section: $section"
    
    # Empty the temporary file if it exists
    > "$temp_file"
    if [[ $? -ne 0 ]]; then
        log "Failed to empty temporary file $temp_file"
        exit 1
    fi
    
    # Read URLs from the configuration file under the specified section
    urls=$(awk -v section="$section" '
        $1 == "[" section "]" { in_section = 1; next }
        in_section && /^\[.*\]/ { exit }
        in_section && NF { print }
    ' "$config_file")
    
    # Download files in parallel and append to the temporary file
    echo "$urls" | xargs -n 1 -P "$parallel_downloads" -I {} bash -c '
        temp_download=$(download_url "$1")
        if [[ -n "$temp_download" ]]; then
            cat "$temp_download" >> "'"$temp_file"'"
        fi
    ' _ {}
    
    # Only split and overwrite final files if the temp file is not empty
    if [[ -s "$temp_file" ]]; then
        temp_file_size=$(stat -c%s "$temp_file")
        log "Temporary file size before splitting: $temp_file_size bytes"
        log "Splitting $temp_file into parts with a maximum of $max_lines lines each"
        split -l "$max_lines" "$temp_file" "${output_file_base}_"
        if [[ $? -eq 0 ]]; then
            log "Successfully split $temp_file into parts with prefix $output_file_base"
        else
            log "Failed to split $temp_file"
            exit 1
        fi
    else
        log "No content to split in $temp_file for section $section. Retaining previous files."
    fi
    
    log "Files processed and saved to $output_dir"
}

# Process IP input feeds
process_section "IPIN_FEEDS" "$output_dir/ipin_list_part"

# Process URL feeds
process_section "URL_FEEDS" "$output_dir/url_list_part"

# Process hash feeds
process_section "HASH_FEEDS" "$output_dir/hash_list_part"

# Process IP output feeds
process_section "IPOUT_FEEDS" "$output_dir/ipout_list_part"

log "Script execution completed. Check the log file for details: $log_file"
