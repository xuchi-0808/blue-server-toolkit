#!/bin/bash
# start-docker-A5.sh — Ascend 950 Products (Atlas 800I A5) 启动脚本
# Version: 1.0
# 用法: bash start-docker-A5.sh <image_id> <container_name>
# A5: 需要额外设备 /dev/ummu /dev/uburma，使用 --runtime=runc

IMAGES_ID=$1
NAME=$2

if [ $# -ne 2 ]; then
    echo "error: usage: $0 <images_id> <name>"
    exit 1
fi

docker run --runtime=runc -u root -it -d --name ${NAME} \
    --net=host --privileged=true --shm-size=128g \
    --device=/dev/davinci_manager --device=/dev/hisi_hdc \
    --device=/dev/ummu --device=/dev/uburma \
    --device=/dev/davinci0 \
    --device=/dev/davinci1 \
    --device=/dev/davinci2 \
    --device=/dev/davinci3 \
    --device=/dev/davinci4 \
    --device=/dev/davinci5 \
    --device=/dev/davinci6 \
    --device=/dev/davinci7 \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/Ascend/firmware:/usr/local/Ascend/firmware \
    -v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /etc/hccl_rootinfo.json:/etc/hccl_rootinfo.json \
    -v /etc/ascend_install.info:/etc/ascend_install.info \
    -v /var/log/npu/:/usr/slog \
    -v /root/host:/root/host \
    -v /mnt:/mnt \
    -v /data:/data \
    -v /home/:/home/ \
    -v /etc/hixlep:/etc/hixlep \
    ${IMAGES_ID}
