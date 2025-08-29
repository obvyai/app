#!/bin/bash
# Build script for SageMaker model container

set -e

# Configuration
PROJECT_NAME="obvy-imggen"
MODEL_NAME="stable-diffusion-xl"
IMAGE_TAG=${1:-latest}
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ECR repository name
ECR_REPO="${PROJECT_NAME}-model"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

echo "Building SageMaker model container..."
echo "Project: ${PROJECT_NAME}"
echo "Model: ${MODEL_NAME}"
echo "Tag: ${IMAGE_TAG}"
echo "ECR URI: ${ECR_URI}"

# Build Docker image
echo "Building Docker image..."
docker build -t ${ECR_REPO}:${IMAGE_TAG} .

# Tag for ECR
docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:latest

echo "Build completed successfully!"
echo "Local image: ${ECR_REPO}:${IMAGE_TAG}"
echo "ECR image: ${ECR_URI}:${IMAGE_TAG}"

# Test the container locally (optional)
if [ "$2" = "test" ]; then
    echo "Testing container locally..."
    docker run --rm --gpus all -p 8080:8080 \
        -e MODEL_ID=stabilityai/stable-diffusion-xl-base-1.0 \
        -e MAX_WIDTH=1024 \
        -e MAX_HEIGHT=1024 \
        -e MAX_STEPS=50 \
        ${ECR_REPO}:${IMAGE_TAG} \
        --prompt "a beautiful sunset over mountains" \
        --steps 20 \
        --width 512 \
        --height 512 \
        --output test_image.png
fi