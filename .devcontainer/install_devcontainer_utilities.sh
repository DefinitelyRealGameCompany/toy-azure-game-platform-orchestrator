#!/bin/bash

TF_ENV_VERSION="v3.0.0"

apt update -y
apt install -y python3-pip

pip3 install pre-commit

mkdir /apps/
git clone --depth=1 -b $TF_ENV_VERSION https://github.com/tfutils/tfenv.git /apps/.tfenv
chmod 777 /apps/.tfenv

curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip \
    && ./aws/install \
    && rm awscliv2.zip


# Install using instrustions from: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt

sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
  gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

AZ_DIST=$(lsb_release -cs)
echo "Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${AZ_DIST}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/azure-cli.sources

sudo apt update -y

# Store an Azure CLI version of choice
AZ_VER=2.69.0
# Install a specific version
sudo apt-get install -y azure-cli=${AZ_VER}-1~${AZ_DIST}


echo 'source /scripts/configure_devcontainer_environment.sh' >> /home/vscode/.bashrc

echo 'source /scripts/devcontainer_runtime_startup.sh' >> /home/vscode/.bashrc
