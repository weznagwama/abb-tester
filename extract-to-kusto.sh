#!/bin/bash

# Script to extract network monitoring data and format for Kusto datatable
# Usage: ./extract-to-kusto.sh

RESULTS_DIR="./results"
OUTPUT_FILE="kusto_datatable.kql"

echo "Processing network monitoring files to create Kusto datatable..."

# Start the datatable definition
cat > "$OUTPUT_FILE" << 'EOF'
datatable(timestamp: datetime, type: string, dstIp: string, observableType: string, observableValue: string) [
EOF

# Counter for comma management
first_entry=true

# Process all files in results directory
for file in "$RESULTS_DIR"/*.txt; do
    if [[ ! -f "$file" ]]; then
        continue
    fi
    
    # Extract filename without path and extension
    filename=$(basename "$file" .txt)
    
    # Parse filename: IP_TYPE_YYYYMMDD_HHMMSS
    # Example: 1.1.1.1_ping_20251221_053553
    IFS='_' read -ra PARTS <<< "$filename"
    
    if [[ ${#PARTS[@]} -lt 4 ]]; then
        echo "Warning: Skipping malformed filename: $filename"
        continue
    fi
    
    # Extract components
    dst_ip="${PARTS[0]}"
    test_type="${PARTS[1]}"
    date_part="${PARTS[2]}"
    time_part="${PARTS[3]}"
    
    # Handle IP addresses with dots (they get split by IFS)
    if [[ ${#PARTS[@]} -gt 4 ]]; then
        # Reconstruct IP address
        dst_ip="${PARTS[0]}.${PARTS[1]}.${PARTS[2]}.${PARTS[3]}"
        test_type="${PARTS[4]}"
        date_part="${PARTS[5]}"
        time_part="${PARTS[6]}"
    fi
    
    # Convert date/time to ISO format
    # YYYYMMDD_HHMMSS -> YYYY-MM-DDTHH:MM:SS.000Z
    year="${date_part:0:4}"
    month="${date_part:4:2}"
    day="${date_part:6:2}"
    hour="${time_part:0:2}"
    minute="${time_part:2:2}"
    second="${time_part:4:2}"
    
    timestamp="${year}-${month}-${day}T${hour}:${minute}:${second}.000Z"
    
    # Extract observable value based on file type
    observable_value=""
    observable_type=""
    
    if [[ "$test_type" == "ping" ]]; then
        # Extract packet loss percentage from ping file
        observable_type="Packet Loss (percent)"
        
        # Look for pattern like "36% packet loss"
        packet_loss=$(grep -o '[0-9]\+% packet loss' "$file" | grep -o '[0-9]\+' | head -1)
        
        if [[ -n "$packet_loss" ]]; then
            observable_value="$packet_loss"
        else
            echo "Warning: No packet loss found in $filename"
            continue
        fi
        
    elif [[ "$test_type" == "tracepath" ]]; then
        # Extract latency to 10.241.5.62 from tracepath file
        observable_type="Latency to ABB internal network"
        
        # Look for line with 10.241.5.62 and extract the latency
        latency_line=$(grep "10\.241\.5\.62" "$file" | head -1)
        
        if [[ -n "$latency_line" ]]; then
            # Extract latency value (number followed by 'ms')
            latency=$(echo "$latency_line" | grep -o '[0-9]\+\.[0-9]\+ms' | grep -o '[0-9]\+\.[0-9]\+' | head -1)
            
            if [[ -n "$latency" ]]; then
                observable_value="$latency"
            else
                echo "Warning: No latency value found for 10.241.5.62 in $filename"
                continue
            fi
        else
            echo "Warning: 10.241.5.62 not found in $filename"
            continue
        fi
        
    else
        echo "Warning: Unknown test type '$test_type' in $filename"
        continue
    fi
    
    # Add comma before entry if not the first
    if [[ "$first_entry" = true ]]; then
        first_entry=false
    else
        echo "," >> "$OUTPUT_FILE"
    fi
    
    # Write the datatable entry
    printf "    datetime(%s), '%s', '%s', '%s', '%s'" \
        "$timestamp" "$test_type" "$dst_ip" "$observable_type" "$observable_value" >> "$OUTPUT_FILE"
    
    echo "Processed: $filename -> $observable_type = $observable_value"
done

# Close the datatable
echo "" >> "$OUTPUT_FILE"
echo "]" >> "$OUTPUT_FILE"

echo ""
echo "Kusto datatable created in: $OUTPUT_FILE"
echo "Total entries processed."

# Show first few lines of output
echo ""
echo "Preview of generated datatable:"
head -10 "$OUTPUT_FILE"
echo "..."
tail -3 "$OUTPUT_FILE"