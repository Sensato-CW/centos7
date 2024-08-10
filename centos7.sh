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
    # Ensure the key does not include unintended data
    encoded_key=$(echo -n "$encoded_key" | tr -d '[:space:]')

    # Debugging: Check the length of the encoded key
    echo "Length of encoded key: $(echo -n "$encoded_key" | wc -c)"

    # Decode the base64 key and write directly to the client.keys file
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

# Debugging: Print the license key before using it
echo "License key before creating client.keys: $license_key"

# Create the client keys file
create_client_keys "$license_key"

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

# Start the OSSEC service
sudo /var/ossec/bin/ossec-control start

# Clean up CSV file
sudo rm "$CSV_PATH"

echo "Automated CloudWave HIDS installation script finished."
