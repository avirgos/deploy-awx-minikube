#!/bin/bash

######################################################################
# Template
######################################################################
set -o errexit  # Exit if command failed.
set -o pipefail # Exit if pipe failed.
set -o nounset  # Exit if variable not set.
IFS=$'\n\t'     # Remove the initial space and instead use '\n'.

######################################################################
# Global variables
######################################################################
# To be modified by user #
##########################
GIT_TAG="2.19.1"
##########################
AWX_DIR=""${HOME}"/awx-operator"
GIT_REPO_AWX_OPERATOR="https://github.com/ansible/awx-operator.git"
AWX_TEMPLATE_FILE=""${AWX_DIR}"/awx-demo.yml"
# path to the Ansible AWX manifest file used for deployment
AWX_DEPLOY_FILE=""${AWX_DIR}"/awx.yml"
# Minikube namespace where Ansible AWX will be deployed
NAMESPACE="ansible-awx"
# name of the Kubernetes service
SERVICE="awx-service"
# http://localhost:"${LOCAL_PORT}"
LOCAL_PORT=8080
REMOTE_PORT=80

######################################################################
# Checks if AWX is deployed and ready.
#
# Globals:
#   NAMESPACE
# Locals:
#   web_exists, task_exists, ready_web, ready_task
# Returns:
#   0 if AWX is deployed and ready, 1 otherwise.
######################################################################
function is_awx_deployed() {
    local web_exists=$(kubectl get deployment awx-web -n "${NAMESPACE}" --ignore-not-found)
    local task_exists=$(kubectl get deployment awx-task -n "${NAMESPACE}" --ignore-not-found)

    if [ -n "${web_exists}" ] && [ -n "${task_exists}" ]
    then
        local ready_web=$(kubectl get deployment awx-web -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
        local ready_task=$(kubectl get deployment awx-task -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")

        if [ "${ready_web}" = "1" ] && [ "${ready_task}" = "1" ]
        then
            return 0
        fi
    fi

    return 1
}


######################################################################
# Starts Minikube if not already running.
#
# Returns:
#   None
######################################################################
function ensure_minikube_running() {
    echo "• Checking Minikube status..."  
    
    if ! minikube status | grep -q "Running"
    then
        echo "• Minikube is not running. Starting it..."
        minikube start --driver=docker
    else
        echo "✅ Minikube is already running."
    fi
}

######################################################################
# Clones the AWX Operator repository if not already present.
#
# Globals:
#   AWX_DIR, GIT_REPO_AWX_OPERATOR
# Returns:
#   None
######################################################################
function clone_awx_operator_repo() {
    echo "• Checking if AWX Operator repository is cloned..."
    
    if [ ! -d "${AWX_DIR}" ]
    then
        echo "❌ AWX Operator directory not found at \""${AWX_DIR}"\""
        echo "• Cloning AWX Operator repository..."
        git clone "${GIT_REPO_AWX_OPERATOR}" "${AWX_DIR}"
    fi
}

######################################################################
# Deploys AWX using the operator and manifest.
#
# Globals:
#   AWX_DIR, GIT_TAG, NAMESPACE, AWX_TEMPLATE_FILE, AWX_DEPLOY_FILE
# Returns:
#   None
######################################################################
function deploy_awx() {
    echo "❌ AWX is not deployed. Starting deployment..."
    
    echo "• Switching to AWX Operator version \""${GIT_TAG}"\"..."
    cd "${AWX_DIR}"
    git checkout "${GIT_TAG}"

    echo "• Creating namespace if it doesn't exist..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  
    echo "• Setting \`NAMESPACE=\""${NAMESPACE}"\"\`"
    export NAMESPACE="${NAMESPACE}"
  
    echo "• Deploying AWX Operator..."
    make deploy
 
    echo "• Preparing AWX manifest..."
    cp "${AWX_TEMPLATE_FILE}" "${AWX_DEPLOY_FILE}"
    sed -i 's/awx-demo/awx/g' "${AWX_DEPLOY_FILE}"

    echo "• Applying AWX manifest..."
    kubectl apply -f "${AWX_DEPLOY_FILE}" -n "${NAMESPACE}"

    wait_for_awx_readiness
}

######################################################################
# Waits until AWX components are ready.
#
# Globals:
#   NAMESPACE
# Locals:
#   max_wait, interval, elapsed
# Returns:
#   None
######################################################################
function wait_for_awx_readiness() {
    echo -e "ℹ️ Checking AWX component readiness... (max. 10 minutes)\n"
  
    local max_wait=600  # 10 minutes
    local interval=60
    local elapsed=0

    while ! is_awx_deployed
    do
        if [ "${elapsed}" -ge "${max_wait}" ]
        then
            echo "⚠️  AWX is not ready after 10 minutes. Port-forwarding aborted."
            exit 1
        fi

        echo "• AWX not ready yet. Retrying in "${interval}"s..."
        kubectl get deployment -n "${NAMESPACE}"
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done
    
    sleep 120   # synchronization delay
    
    echo "✅ AWX is ready (\`awx-web\` and \`awx-task\` are available)."
}

######################################################################
# Starts port forwarding to access AWX locally.
#
# Globals:
#   SERVICE, LOCAL_PORT, REMOTE_PORT, NAMESPACE
# Returns:
#   None
######################################################################
function start_port_forwarding() {
    echo "• Checking if port forwarding is already running..."

    if pgrep -f "kubectl port-forward svc/"${SERVICE}" "${LOCAL_PORT}":"${REMOTE_PORT}" -n "${NAMESPACE}"" > /dev/null
    then
        echo "✅ Port forwarding is already running. AWX should be accessible at \"http://localhost:${LOCAL_PORT}\""
    else
        echo "• Starting port forwarding..."
        nohup kubectl port-forward svc/"${SERVICE}" "${LOCAL_PORT}":"${REMOTE_PORT}" -n "${NAMESPACE}" > /dev/null 2>&1 &
        echo "✅ Port forward started. AWX should be accessible at \"http://localhost:${LOCAL_PORT}\""
    fi
}

######################################################################
# Retrieves the `admin` password from the Ansible AWX secret.
#
# Globals:
#   NAMESPACE
# Locals:
#   secret_username_admin, admin_password
# Returns:
#   None 
######################################################################
function retrieve_admin_password() {
    local secret_username_admin=$(kubectl get secret -n "${NAMESPACE}" | grep -i password | cut -d ' ' -f1)
    local admin_password=$(kubectl get secret "${secret_username_admin}" -o jsonpath="{.data.password}" -n "${NAMESPACE}" | base64 --decode)
    
    echo "🔒 \`admin\` password account: "${admin_password}""
}

######################################################################
# Main program
######################################################################
ensure_minikube_running

echo "• Checking if AWX is deployed..."
if ! is_awx_deployed
then
    clone_awx_operator_repo
    deploy_awx
else
    echo "✅ AWX is already deployed."
fi

start_port_forwarding
retrieve_admin_password
