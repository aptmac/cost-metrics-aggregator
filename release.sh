#!/bin/bash

set -exv

IMAGE_NAME="quay.io/almacdon/cost-metrics-aggregator"
IMAGE_TAG=$(git rev-parse --short=7 HEAD)

podman build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
podman tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:latest"

podman push "${IMAGE_NAME}:${IMAGE_TAG}"
podman push "${IMAGE_NAME}:latest"
