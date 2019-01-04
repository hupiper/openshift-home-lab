#!/bin/bash

source ./env.sh

# verify a bunch of variables have contents, as a sanity check
if [ ! -v VMS ]; then
	echo "${VMS} is not defined. Please set this in env.sh and try again."
	exit 1
fi
if [ ! -v CLUSTERKEY ]; then
	echo "${CLUSTERKEY} is not defined. Please set this in env.sh and try again."
	exit 2
fi
if [ ! -v ORIGINALKEY ]; then
	echo "${ORIGINALKEY} is not defined. Please set this in env.sh and try again."
	exit 3
fi
if [ ! -v VMROOTDISK ]; then
	echo "${VMROOTDISK} is not defined. Please set this in env.sh and try again."
	exit 4
fi
if [ ! -v INITIALPASSWD ]; then
	echo "${INITIALPASSWD} is not defined. Please set this in env.sh and try again."
	exit 5
fi

# create the VM directory if it doesn't exist
if [ ! -d "$VMS" ]
then
    echo "Creating ${VMS}"
    mkdir -p "$VMS"
fi

# sanity checks around the ssh key stuff
if [ ! -f "$CLUSTERKEY" ]; then # if the cluster sshkey doesn't exist, try to copy it from the original key
	if [ ! -r "$ORIGINALKEY" ]; then # check to see if the original key exists and is readable
		echo "${CLUSTERKEY} does not exist, and ${ORIGINALKEY} can't be found/read."
		exit 6
	fi

	# if CLUSTERKEY doesn't exist, but the ORIGINALKEY does, copy it. 
	cp "$ORIGINALKEY" "$CLUSTERKEY"
	COPYRESULT=$?
	if [ "$COPYRESULT" -ne 0 ]; then
		echo "Error: Copying ${ORIGINALKEY} to create ${CLUSTERKEY} failed with: ${COPYRESULT}"
		exit 7
	fi
fi
if [ ! -r "$CLUSTERKEY" ]; then # bomb out if the cluster sshkey isn't readable
	echo "${CLUSTERKEY} is missing, or is not readbale. Exiting now."
	exit 8
fi

# ensure that the permissions are correct for the new cluster key
chmod 644 "$CLUSTERKEY"

for i in `cat hosts|grep -v \\\\[`;
do 
    echo "########################################################################"
    echo "[${i} start]"

    BASEIMAGE="${VMS}/${i}-base.qcow2"
    IMAGE="${VMS}/${i}.qcow2"
    DOCKERDISK="${VMS}/${i}-docker.qcow2"
    GLUSTERFSDISK="${VMS}/${i}-glusterfs.qcow2"

    echo "[Creating a ${VMROOTDISK} disk for root, ${IMAGE}]"
    qemu-img create -f qcow2 "$BASEIMAGE" "$VMROOTDISK"
    virt-resize --expand /dev/sda1 "$RHEL_IMAGE" "$BASEIMAGE"
    qemu-img create -f qcow2 -b "$BASEIMAGE" "$IMAGE"

    echo "[Creating a ${VMDOCKERDISK} disk for docker, ${DOCKERDISK}]"
    qemu-img create -f raw "$DOCKERDISK" "$VMDOCKERDISK"

    echo "[Creating a ${VMGLUSTERFSDISK} disk for glusterfs, ${GLUSTERFSDISK}]"
    qemu-img create -f raw "$GLUSTERFSDISK" "$VMGLUSTERFSDISK"

    echo "[Customizing ${i} system]"
    virt-customize -a "$IMAGE" --run-command 'yum remove cloud-init* -y'
    virt-customize -a "$IMAGE" --root-password password:"$INITIALPASSWD"
    virt-customize -a "$IMAGE" --ssh-inject root:file:"$CLUSTERKEY"
    virt-customize -a "$IMAGE" --hostname "$i"
    echo "[${i} done]"
done
