# SageMaker Inference Container for Stable Diffusion
FROM nvidia/cuda:11.8-devel-ubuntu20.04

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/miniconda/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/miniconda && \
    rm /tmp/miniconda.sh

# Create conda environment
RUN conda create -n sagemaker python=3.10 -y
SHELL ["conda", "run", "-n", "sagemaker", "/bin/bash", "-c"]

# Install PyTorch with CUDA support
RUN pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu118

# Install core ML libraries
RUN pip install \
    transformers==4.35.0 \
    diffusers==0.24.0 \
    accelerate==0.24.0 \
    xformers==0.0.22.post7 \
    safetensors==0.4.0 \
    Pillow==10.0.1 \
    numpy==1.24.3 \
    scipy==1.11.3

# Install SageMaker dependencies
RUN pip install \
    sagemaker-inference==1.7.0 \
    boto3==1.29.0 \
    botocore==1.32.0

# Install additional utilities
RUN pip install \
    requests==2.31.0 \
    psutil==5.9.6 \
    GPUtil==1.4.0

# Set up model directory
RUN mkdir -p /opt/ml/model /opt/ml/code /tmp/model_cache /tmp/transformers_cache /tmp/huggingface_cache

# Copy inference code
COPY inference.py /opt/ml/code/inference.py
COPY requirements.txt /opt/ml/code/requirements.txt

# Set environment variables for model caching
ENV MODEL_CACHE_ROOT=/tmp/model_cache
ENV TRANSFORMERS_CACHE=/tmp/transformers_cache
ENV HF_HOME=/tmp/huggingface_cache
ENV TORCH_HOME=/tmp/torch_cache

# Set working directory
WORKDIR /opt/ml/code

# Expose port for SageMaker
EXPOSE 8080

# Set the conda environment as default
RUN echo "conda activate sagemaker" >> ~/.bashrc
ENV PATH /opt/miniconda/envs/sagemaker/bin:$PATH

# Entry point for SageMaker
ENTRYPOINT ["python", "inference.py"]