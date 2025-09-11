# deploy-awx-minikube

## Overview

Bash script to deploy Ansible AWX using Minikube.

## Features

- **Continuous display** of the deployment process
- **Port forwarding** to use Ansible AWX locally
- If Ansible AWX is already deployed and port forwarding is not running, **only** port forwarding is started
- **`admin` password displayed** to connect to Ansible AWX dashboard

## Prerequisites

The following packages are required:

- [`minikube`](https://minikube.sigs.k8s.io/docs/start/?arch=%2Flinux%2Fx86-64%2Fstable%2Fbinary+download)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-binary-with-curl-on-linux)
- `git`
- `make`

## Usage

Run the following Bash script:

```bash
./deploy-awx-minikube.sh
```

## Configuration

⚠️  To deploy Ansible AWX, the script uses [`awx-operator` Git repository](https://github.com/ansible/awx-operator/releases) and `latest` version must be defined ⚠️:

```bash
GIT_TAG="2.19.1"
```

Also, in this script, you can modify these variables if necessary:

```bash
# path to the Ansible AWX manifest file used for deployment
AWX_DEPLOY_FILE=""${AWX_DIR}"/awx.yml"
# Minikube namespace where Ansible AWX will be deployed
NAMESPACE="ansible-awx"
# name of the Kubernetes service
SERVICE="awx-service"
# http://localhost:"${LOCAL_PORT}"
LOCAL_PORT=8080
```
