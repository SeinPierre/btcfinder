#!/bin/bash
# user_data.sh

# Update system
yum update -y

# Install dependencies
yum install -y git gcc openssl-dev pkg-config

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env

# Create application directory
mkdir -p /opt/bitcoin-matcher
cd /opt/bitcoin-matcher

# Create systemd service file
cat << 'EOF' > /etc/systemd/system/bitcoin-matcher.service
[Unit]
Description=Bitcoin Address Matcher
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/bitcoin-matcher
ExecStart=/opt/bitcoin-matcher/target/release/bitcoin-matcher
Restart=always
Environment=BUCKET_NAME=${bucket_name}

[Install]
WantedBy=multi-user.target
EOF

# Set ownership
chown -R ec2-user:ec2-user /opt/bitcoin-matcher

# Enable service
systemctl daemon-reload
systemctl enable bitcoin-matcher