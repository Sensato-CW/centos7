#!/bin/bash

# Variables
OSSEC_DIR="/var/ossec"
CSV_URL="https://raw.githubusercontent.com/Sensato-CW/Linux-Agent/main/Install%20Script/HIDS%20Keys.csv"
CSV_PATH="/tmp/HIDS_Keys.csv"
SERVER_IP="10.0.3.126"
AGENT_CONF="/var/ossec/etc/ossec-agent.conf"

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
    elif command -v python3 > /dev/null || command -v python > /dev/null; then
        python_version=$(command -v python3 > /dev/null && echo "python3" || echo "python")
        sudo $python_version -c "
import urllib.request
try:
    urllib.request.urlretrieve('$CSV_URL', '$CSV_PATH')
    print('HIDS Keys CSV file downloaded successfully.')
except Exception as e:
    print(f'Failed to download HIDS Keys CSV file with Python. Installation aborted: {e}')
    exit(1)
" || exit 1
    else
        echo "No suitable download tool available (wget, curl, python). Installation aborted."
        exit 1
    fi

    echo "HIDS Keys CSV file downloaded successfully."
    sleep 3
}

# Function to get the hostname without the domain
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

    # Read the CSV file and check for the system name
    while IFS=, read -r id asset_name asset_type source_ip key; do
        # Trim any leading or trailing whitespace from variables
        asset_name=$(echo "$asset_name" | xargs)
        key=$(echo "$key" | xargs)

        # Skip empty lines or headers
        if [[ -z "$id" || "$id" == "ID" ]]; then
            continue
        fi

        # Check if the asset name matches the hostname
        if [[ "$asset_name" == "$HOSTNAME" ]]; then
            license_key="$key"
            found=1
            break
        fi
    done < "$CSV_PATH"

    # If not found, set an error message
    if [[ $found -ne 1 ]]; then
        echo "System is not licensed for CloudWave HIDS Agent. Installation aborted."
        exit 1
    fi

    # Return the key
    echo "$license_key"
}

# Function to create the client.keys file for agent authentication
create_client_keys() {
    local encoded_key="$1"

    echo "Creating client.keys file..."
    echo "Encoded key received: '$encoded_key'"  # Debug line to show the received key

    # Trim any whitespace or newlines from the key
    encoded_key=$(echo -n "$encoded_key" | tr -d '[:space:]')

    # Decode the base64 key and write directly to the client.keys file
    decoded_key=$(echo -n "$encoded_key" | base64 --decode)
    if [ $? -eq 0 ]; then
        echo "$decoded_key" | sudo tee /var/ossec/etc/client.keys > /dev/null
        echo "client.keys file created successfully."
    else
        echo "Failed to decode the key. Please check the key format."
        exit 1
    fi

    sleep 3
}

# Function to update the agent configuration with the correct server IP
update_agent_conf() {
    echo "Updating ossec-agent.conf with server IP: $SERVER_IP"

    # Check for existing server-ip entry and replace it
    if grep -q "<server-ip>" "$AGENT_CONF"; then
        sudo sed -i "s|<server-ip>.*</server-ip>|<server-ip>$SERVER_IP</server-ip>|" "$AGENT_CONF"
    else
        # If no server-ip entry is found, add it
        echo "<ossec_config><client><server-ip>$SERVER_IP</server-ip></client></ossec_config>" | sudo tee -a "$AGENT_CONF" > /dev/null
    fi

    # Check and remove any duplicates if needed
    awk '!seen[$0]++' "$AGENT_CONF" > /tmp/ossec-agent.tmp && sudo mv /tmp/ossec-agent.tmp "$AGENT_CONF"

    echo "Agent configuration updated successfully."
}

# Start the installation process
download_csv
get_system_name

# Perform yum update and install dependencies
echo "Performing yum update."
sudo yum clean all
sudo yum update -y
sudo yum makecache

echo "Installing dependencies for CloudWave HIDS."
sudo yum --enablerepo=base,updates,extras install -y perl gcc make zlib-devel pcre2-devel libevent-devel curl wget git expect

# Download the installer script
echo "Retrieving Installer."
wget -q -O atomic-installer.sh https://updates.atomicorp.com/installers/atomic

# Make the installer executable
chmod +x atomic-installer.sh

# Automate installation using expect
echo "Automating installation."
expect <<- EOF
spawn sudo ./atomic-installer.sh
expect "Do you agree to these terms?" { send "yes\r" }
expect eof
EOF

# Install OSSEC HIDS agent
echo "Installing HIDS agent."
sudo yum install -y ossec-hids-agent

sleep 5

# Clean up the installer script
rm atomic-installer.sh

# Retrieve the license key after installation
license_key=$(check_license)

# If the key is valid, create the client.keys file and update the configuration
if [ -n "$license_key" ]; then
    create_client_keys "$license_key"
    update_agent_conf

    # Start the OSSEC services
    sudo /var/ossec/bin/ossec-control restart
	

    echo "Automated CloudWave HIDS installation script finished."
else
    echo "No valid license key found. Installation aborted."
    exit 1
fi
