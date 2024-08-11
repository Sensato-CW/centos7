#!/bin/bash

# Variables
OSSEC_DIR="/var/ossec"
CSV_URL="https://raw.githubusercontent.com/Sensato-CW/Linux-Agent/main/Install%20Script/HIDS%20Keys.csv"
CSV_PATH="/tmp/HIDS_Keys.csv"
SERVER_IP="10.0.3.126"
AGENT_CONF="$OSSEC_DIR/etc/ossec-agent.conf"
OSSEC_CONF="$OSSEC_DIR/etc/ossec.conf"
INTERNAL_OPTIONS="$OSSEC_DIR/etc/internal_options.conf"

# Backup existing repo settings
echo "Backing up repository settings."
sudo cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak

# Function to download the HIDS Keys CSV file
download_csv() {
    echo "Downloading HIDS Keys CSV file..."

    # Remove existing file if it exists
    if [ -f "$CSV_PATH" ]; then
        sudo rm -f "$CSV_PATH"
    fi

    # Download using available tools
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

# Function to retrieve the license key
retrieve_license_key() {
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

    echo "$license_key"
}

# Function to create the client.keys file for agent authentication
create_client_keys() {
    local license_key="$1"

    echo "Creating client.keys file..."
    echo "Encoded key received: '$license_key'"  # Debug line to show the received key

    # Trim any whitespace or newlines from the key
    license_key=$(echo -n "$license_key" | tr -d '[:space:]')

    # Decode the base64 key and write directly to the client.keys file
    decoded_key=$(echo -n "$license_key" | base64 --decode)
    if [ $? -eq 0 ]; then
        echo "$decoded_key" | sudo tee /var/ossec/etc/client.keys > /dev/null
        echo "client.keys file created successfully."
        sleep 2
    else
        echo "Failed to decode the key. Please check the key format."
        exit 1
    fi

    sleep 3
}

# Function to update the agent configuration with the correct server IP
update_agent_conf() {
    echo "Updating ossec-agent.conf with server IP: $SERVER_IP"

    # Check if the file exists
    if [ ! -f "$AGENT_CONF" ]; then
        echo "Agent configuration file not found at $AGENT_CONF"
        exit 1
    fi

    # Replace or add the server-ip entry in ossec-agent.conf
    if grep -q "<server-ip>" "$AGENT_CONF"; then
        sudo sed -i "s|<server-ip>.*</server-ip>|<server-ip>$SERVER_IP</server-ip>|" "$AGENT_CONF"
    else
        # Insert the server-ip entry before the closing </ossec_config> tag
        sudo sed -i "/<\/ossec_config>/i <client><server-ip>$SERVER_IP</server-ip></client>" "$AGENT_CONF"
    fi

    echo "Agent configuration updated successfully."
}

# Function to remove duplicate entries from ossec.conf
remove_entries_from_ossec_conf() {
    echo "Removing duplicate entries from ossec.conf."

    sudo sed -i 's|/etc</directories>|<!-- /etc</directories> -->|g' "$OSSEC_CONF"
    sudo sed -i 's|/bin</directories>|<!-- /bin</directories> -->|g' "$OSSEC_CONF"

    echo "Duplicate entries removed from ossec.conf."
}

# Function to update internal_options.conf
update_internal_options() {
    echo "Updating internal_options.conf for remote commands."

    if grep -q "logcollector.remote_commands" "$INTERNAL_OPTIONS"; then
        sudo sed -i 's/^logcollector.remote_commands=.*/logcollector.remote_commands=1/' "$INTERNAL_OPTIONS"
    else
        echo "logcollector.remote_commands=1" | sudo tee -a "$INTERNAL_OPTIONS" > /dev/null
    fi

    echo "internal_options.conf updated successfully."
}

# Main script flow

# Download the CSV file
download_csv

# Get the system name
get_system_name

# Retrieve the license key before proceeding with installation
license_key=$(retrieve_license_key)

# Debugging: Print the license key before using it
echo "License key before creating client.keys: $license_key"

# Update repo URLs
echo "Updating the repository."
sudo sed -i 's|^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra|' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|^#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/|baseurl=http://vault.centos.org/centos/$releasever/os/$basearch/|' /etc/yum.repos.d/CentOS-Base.repo

sudo sed -i 's|^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates&infra=$infra|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates&infra=$infra|' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|^#baseurl=http://mirror.centos.org/centos/$releasever/updates/$basearch/|baseurl=http://vault.centos.org/centos/$releasever/updates/$basearch/|' /etc/yum.repos.d/CentOS-Base.repo

sudo sed -i 's|^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras&infra=$infra|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras&infra=$infra|' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|^#baseurl=http://mirror.centos.org/centos/$releasever/extras/$basearch/|baseurl=http://vault.centos.org/centos/$releasever/extras/$basearch/|' /etc/yum.repos.d/CentOS-Base.repo

sudo sed -i 's|^enabled=1|enabled=0|' /etc/yum.repos.d/CentOS-Base.repo

# Perform yum update
echo "Performing yum update."
sudo yum clean all
sudo yum update -y
sudo yum makecache

# Install dependencies
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

# Clean up the installer script
rm atomic-installer.sh

# Add a delay to ensure the installation process completes
sleep 5

# After installation, create the client keys file and set the server
create_client_keys "$license_key"

# Update the agent configuration to include the server IP
update_agent_conf

# Remove duplicate entries from ossec.conf
remove_entries_from_ossec_conf

# Update internal_options.conf to allow remote commands
update_internal_options

# Start the OSSEC service
sudo /var/ossec/bin/ossec-control start

# Clean up CSV file
sudo rm "$CSV_PATH"

echo "Automated CloudWave HIDS installation script finished."