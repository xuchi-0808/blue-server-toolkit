#!/bin/bash
# start-docker-A2.sh — Atlas 800I A2 启动脚本
# Version: 1.0
# 用法: bash start-docker-A2.sh <image_id> <container_name>
# A2: 8 NPU（单芯），davinci0-7

IMAGES_ID=$1
NAME=$2

if [ $# -ne 2 ]; then
    echo "error: usage: $0 <images_id> <name>"
    exit 1
fi

docker run --name ${NAME} -it -d --net=host --shm-size=128g \
    --privileged=true \
    -w /home \
    --device=/dev/davinci_manager \
    --device=/dev/hisi_hdc \
    --device=/dev/devmm_svm \
    --device=/dev/davinci0 \
    --device=/dev/davinci1 \
    --device=/dev/davinci2 \
    --device=/dev/davinci3 \
    --device=/dev/davinci4 \
    --device=/dev/davinci5 \
    --device=/dev/davinci6 \
    --device=/dev/davinci7 \
    --entrypoint=bash \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /etc/ascend_install.info:/etc/ascend_install.info \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /home:/home \
    -v /data:/data \
    -v /tmp:/tmp \
    -v /mnt:/mnt \
    -v /usr/share/zoneinfo/Asia/Shanghai:/etc/localtime \
    -v /root:/host_root \
    ${IMAGES_ID}
