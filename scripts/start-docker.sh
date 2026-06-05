#!/bin/bash
# blue_server_toolkit - Start Docker Container
# Version: 0.9
# Creates a Docker container with Ascend NPU device mappings and data mounts.
#
# Usage: bash start-docker.sh <image_id> <container_name>

IMAGES_ID=$1
NAME=$2
if [ $# -ne 2 ]; then
    echo "Usage: bash start-docker.sh <image_id> <container_name>"
    exit 1
fi
docker run --name ${NAME} -it -d --net=host --shm-size=500g \
    --privileged=true \
    -w /home \
    --device=/dev/davinci_manager \
    --device=/dev/hisi_hdc \
    --device=/dev/devmm_svm \
    --entrypoint=bash \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /etc/ascend_install.info:/etc/ascend_install.info \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /home:/home \
    -v /data:/data \
    -v /data1:/data1 \
    -v /tmp:/tmp \
    -v /mnt:/mnt \
    -v /usr/share/zoneinfo/Asia/Shanghai:/etc/localtime \
    -v /root:/host_root \
    ${IMAGES_ID}
