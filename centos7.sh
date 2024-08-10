#!/bin/bash

# Variables
OSSEC_DIR="/var/ossec"
CSV_URL="https://raw.githubusercontent.com/Sensato-CW/Linux-Agent/main/Install%20Script/HIDS%20Keys.csv"
CSV_PATH="/tmp/HIDS_Keys.csv"
SERVER_IP="10.0.3.126"

# Backup existing repo settings
echo "Backing up repository settings."
sudo cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak

# Function to download the HIDS Keys CSV file
download_csv() {
    echo "Downloading HIDS Keys CSV file..."
    if [ -f "$CSV_PATH" ]; then
        sudo rm -f "$CSV_PATH"
    fi
    if command -v wget > /dev/null; then
        sudo wget -q -O "$CSV_PATH" "$CSV_URL" || { echo "Failed to download HIDS Keys CSV file with wget. Installation aborted."; exit 1; }
    elif command -v curl > /dev/null; then
        sudo curl -sS -o "$CSV_PATH" "$CSV_URL" || { echo "Failed to download HIDS Keys CSV file with curl. Installation aborted."; exit 1; }
    else
        echo "No suitable download tool available. Installation aborted."
        exit 1
    fi
    echo "HIDS Keys CSV file downloaded successfully."
    sleep 3
}

# Function to get the short hostname without the domain
get_system_name() {
    HOSTNAME=$(hostname -s)
    echo "System name: $HOSTNAME"
    sleep 3
}

# Function to check if the system is licensed and retrieve the key
check_license() {
    if [ ! -f "$CSV_PATH" ]; then
        echo "License file not found at $CSV_PATH"
        exit 1
    fi

    local license_key=""
    local found=0
    short_hostname=$(echo "$HOSTNAME" | cut -d. -f1)

    while IFS=, read -r id asset_name asset_type source_ip key; do
        asset_name=$(echo "$asset_name" | xargs)
        key=$(echo "$key" | xargs)
        echo "Debugging: Comparing trimmed AssetName='$asset_name' with trimmed HOSTNAME='$short_hostname'"
        if [[ "$asset_name" == "$short_hostname" ]]; then
            license_key="$key"
            found=1
            break
        fi
    done < "$CSV_PATH"

    if [[ $found -ne 1 ]]; then
        echo "System is not licensed for CloudWave HIDS Agent. Installation aborted."
        exit 1
    fi

    echo "$license_key"
}

# Function to create the client.keys file for agent authentication
create_client_keys() {
    local encoded_key="$1"

    echo "Creating client.keys file..."
    encoded_key=$(echo -n "$encoded_key" | tr -d '[:space:]')
    decoded_key=$(echo -n "$encoded_key" | base64 --decode 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "$decoded_key" | sudo tee /var/ossec/etc/client.keys > /dev/null
        echo "client.keys file created successfully."
    else
        echo "Failed to decode the key. Please check the key format."
        exit 1
    fi

    sleep 3
}

# Download the CSV file
download_csv

# Get the system name
get_system_name

# Retrieve the license key
license_key=$(check_license)

# Halt if the license key was not found
if [ -z "$license_key" ]; then
    echo "No valid license key found. Installation aborted."
    exit 1
fi

echo "License key before creating client.keys: $license_key"

# Update repo URLs and perform yum update (omitting for brevity, add your previous yum update commands here)

# Install OSSEC HIDS agent (omitting for brevity, add your previous install commands here)

# Create the client keys file
create_client_keys "$license_key"

# Start the OSSEC service (omitting for brevity, add your previous commands to start the service here)

echo "Automated CloudWave HIDS installation script finished."
