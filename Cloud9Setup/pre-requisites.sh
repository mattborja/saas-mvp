#!/bin/bash -x

# NOTE: Original script assumed Cloud9 (Amazon Linux) with ec2-user. Cloud9 is deprecated.
# This script now works on a generic Linux dev host and ensures AWS CLI is configured.
# If you are not using ec2-user, set NVM_DIR before sourcing.

#Installing NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# shellcheck source=/dev/null
. "$HOME/.nvm/nvm.sh"

# Detect package manager
if command -v yum >/dev/null 2>&1; then
    PKG_MGR=yum
elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR=apt
else
    echo "Unsupported package manager. Install dependencies manually." >&2
    exit 1
fi

PYTHON_BIN=python3.8

#Install python3.8 (prefer system packages matching host OS)
if [ "$PKG_MGR" = "yum" ]; then
    sudo yum install -y amazon-linux-extras
    sudo amazon-linux-extras enable python3.8
    sudo yum install -y python3.8
elif [ "$PKG_MGR" = "apt" ]; then
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt-get update
    sudo apt-get install -y python3.8 python3.8-venv python3.8-dev uuid-runtime
fi

# Supplemental
if [ "$PKG_MGR" = "yum" ]; then
    sudo yum -y install jq-1.5
else
    sudo apt-get install -y jq
fi

# Prefer python3.8 for workshop tooling if available
if command -v python3.8 >/dev/null 2>&1; then
    PYTHON_BIN=python3.8
    $PYTHON_BIN -m ensurepip --upgrade
    $PYTHON_BIN -m pip install --upgrade pip setuptools wheel
else
    PYTHON_BIN=python3
fi

# Uninstall aws cli v1 and Install aws cli version-2.3.0
sudo pip uninstall awscli -y

echo "Installing aws cli version-2.3.0"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.3.0.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -rf aws 

# Install sam cli version 1.64.0
echo "Installing sam cli version 1.64.0"
wget https://github.com/aws/aws-sam-cli/releases/download/v1.64.0/aws-sam-cli-linux-x86_64.zip
unzip aws-sam-cli-linux-x86_64.zip -d sam-installation
sudo ./sam-installation/install
if [ $? -ne 0 ]; then
    echo "Sam cli is already present, so deleting existing version"
    sudo rm /usr/local/bin/sam
    sudo rm -rf /usr/local/aws-sam-cli
    echo "Now installing sam cli version 1.64.0"
    sudo ./sam-installation/install    
fi
rm aws-sam-cli-linux-x86_64.zip
rm -rf sam-installation

# Install git-remote-codecommit version 1.15.1
echo "Installing git-remote-codecommit version 1.15.1"
curl -O https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --user
rm get-pip.py

${PYTHON_BIN} -m pip install git-remote-codecommit==1.15.1

# Install node v14.18.1
echo "Installing node v14.18.1"
nvm deactivate
nvm uninstall node
nvm install v14.18.1
nvm use v14.18.1
nvm alias default v14.18.1

# Install cdk cli version ^2.40.0
echo "Installing cdk cli version ^2.40.0"
npm uninstall -g aws-cdk
npm install -g aws-cdk@"^2.40.0"

#Install pylint version 2.17.5 (works with host python3.12 and targets py3.8/3.9 code)
${PYTHON_BIN} -m pip install pylint==2.17.5

${PYTHON_BIN} -m pip install boto3

# Ensure AWS CLI is configured for non-Cloud9 environments
if ! aws sts get-caller-identity >/dev/null 2>&1; then
	echo "AWS CLI is installed but not configured. Running 'aws configure'..."
	aws configure
fi

REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
	echo "AWS region is not set. Please enter a default region (e.g., us-west-2)."
	aws configure set region "${AWS_REGION:-us-west-2}"
fi

echo "Prerequisites complete. Current caller identity:"
aws sts get-caller-identity
