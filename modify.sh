#!/bin/bash
# Author: Xiangchun Fu (xfu@redhat.com)

namespace = $1

# Function to check if the oc command is available
function check_oc() {
    if ! command -v oc &>/dev/null; then
        echo "oc command not found. Please install the oc CLI tool."
        exit 1
    fi
}

# Check if oc command is available
check_oc

# Modify kata configuraton with 1/2 vcpus and memory host
function add_katacontainer_vcpu_memory() {
    oc get nodes -o=custom-columns=NAME:.metadata.name | sed 1d | while IFS= read -r nodename; do oc debug node/$nodename -- chroot /host; echo "mount -o remount,rw /usr" >>/tmp/add_container_vcpu_mem.sh;echo "let half_memory=$(free -m | grep Mem: | awk '{print $2}')/2" >>/tmp/add_container_vcpu_mem.sh;echo "let half_vcpu=$(lscpu | grep "^CPU(s):" | awk '{print $2}')/2" >>/tmp/add_container_vcpu_mem.sh;echo "sed -i "s/default_vcpus = .*/default_vcpus = ${half_vcpu}/" /usr/kata/share/defaults/kata-containers/configuration-qemu-tdx.toml" >>/tmp/add_container_vcpu_mem.sh;echo "sed -i "s/default_memory .*/default_memory = ${half_memory}/" /usr/kata/share/defaults/kata-containers/configuration-qemu-tdx.toml" >>/tmp/add_container_vcpu_mem.sh; done |exit 1
    oc get nodes -o=custom-columns=NAME:.metadata.name | sed 1d | while IFS= read -r nodename; do oc debug node/$nodename -- chroot /host;chmod +x /tmp/add_container_vcpu_mem.sh;rm -f /tmp/add_container_vcpu_mem.sh |exit 1

}

# Add kbs server IP address to kerenel paras in kata configuration
function add_kbs_ip_kernel_line() {
    kbs_server_ip = `oc get svc -n kbs-operator-system kbs-service -o jsonpath={.spec.clusterIP}`
    oc get nodes -o=custom-columns=NAME:.metadata.name | sed 1d | while IFS= read -r nodename; do oc debug node/$nodename -- chroot /host;sed -i '/kernel_params/s/^\(.*\)$/#\1/g' /usr/kata/share/defaults/kata-containers/configuration-qemu-tdx.toml |exit 1
    oc get nodes -o=custom-columns=NAME:.metadata.name | sed 1d | while IFS= read -r nodename; do oc debug node/$nodename -- chroot /host;echo "kernel_params=agent.aa_kbc_params=cc_kbc::http://`oc get svc -n kbs-operator-system kbs-service -o jsonpath={.spec.clusterIP}`:8080"	

}

#Create 2 local PVs as storage
function create_local_storage(){

    oc apply -n $namesapce -f https://github.com/rh-aiservices-bu/$namesapce/raw/main/setup/setup-s3.yaml | exit 1
    mkdir /tmp/coco_storage1/
    cat >pv01.yaml << EOF
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: hostpath-pv1
    spec:
      capacity:
        storage: 20Gi
      accessModes:
        - ReadWriteOnce
      hostPath:
        path: /tmp/coco_storage1/
        type: DirectoryOrCreate
        readOnly: false
      persistentVolumeReclaimPolicy: Retain

EOF
    oc apply -f pv01.yaml -n $namesapce |exit 1
    chmod 777 /tmp/coco_storage1
    
    mkdir /tmp/coco_storage2/
    cat >pv02.yaml << EOF
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: hostpath-pv2
    spec:
      capacity:
        storage: 20Gi
      accessModes:
        - ReadWriteOnce
      hostPath:
        path: /tmp/coco_storage2/
        type: DirectoryOrCreate
        readOnly: false
      persistentVolumeReclaimPolicy: Retain
EOF
    
    oc apply -f pv02.yaml -n $namesapce |exit 1
    chmod 777 /tmp/coco_stoarge2/
}

#Modify vcpu number and memory size in kata configuration for kata container 
add_katacontainer_vcpu_memory

#Add kbs server IP address to kernel line in kata configuration 
add_kbs_ip_kernel_line

#Create local PVs storage for openshift AI model
create_local_storage

#--------------------------modify configmap runtimeclass secret images....as below---------------------

# Enable runtimeclassname
oc patch cm config-features -p $'data:\n  kubernetes.podspec-runtimeclassname: enabled' -n knative-serving || exit 1

#Set verify_ssl to false
oc label secret/storage-config opendatahub.io/managed=false --overwrite -n $namesapce|exit 1
oc get secret storage-config  -n $namesapce -o jsonpath="{.data['aws-connection-my-storage']}" |base64 -d|sed 's/}/,"verify_ssl":"false"}/' >no_verify_ssl |exit 1
oc patch secret storage-config --type=json --patch "[{'op':'replace','path':'/data/aws-connection-my-storage','value':'$(base64 -w 0 no_verify_ssl )'}]" -n $namesapce |exit 1

# Replace kserver-container image
oc patch ServingRuntime fraud --type='json' -p='[{"op": "replace", "path": "/spec/containers/0/image", "value": "quay.io/modh/openvino_model_server@sha256:5d04d405526ea4ce5b807d0cd199ccf7f71bab1228907c091e975efa770a4908"}]' -n $namesapce |exit 1

# Replace queue container image
oc patch cm config-deployment -p $'data:\n  queue-sidecar-image: quay.io/eesposit/serving-queue-rhel8:latest' -n knative-serving |exit 1

# Set sidecar.istio.io/inject to "false"
oc patch inferenceservices fraud --type='json' -p='[{"op": "replace", "path": "/metadata/annotations/sidecar.istio.io.inject", "value": "false"}]' -n $namesapce |exit 

# Add runtimeClassName: kata-cc-tdx 
oc patch inferenceservices/fraud --type='json' -p='[{"op": "add", "path": "/spec/predictor/runtimeClassName", "value": "kata-cc-tdx"}]' -n $namesapce |exit 1

echo "Fraud detection AI model with CoCo configuration is successfully"
