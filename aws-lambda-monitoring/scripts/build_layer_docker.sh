#!/bin/bash
set -e

echo "🚀 Building Lambda Layer with Pillow using Docker..."

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "📖 Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

echo "📦 Building layer in Linux container (Python 3.12)..."

# Convert Windows path to Docker-compatible format
# Handle both Git Bash (/c/Users/...) and WSL formats
DOCKER_VOLUME=""
if [[ "$TERRAFORM_DIR" =~ ^/([a-z])/ ]]; then
    # Git Bash format: /c/Users/... -> //c/Users/...
    DOCKER_VOLUME="/${TERRAFORM_DIR}"
elif [[ "$TERRAFORM_DIR" =~ ^([A-Z]):/ ]]; then
    # Windows format: C:/Users/... -> //c/Users/...
    DRIVE=$(echo "${TERRAFORM_DIR:0:1}" | tr '[:upper:]' '[:lower:]')
    DOCKER_VOLUME="//${DRIVE}${TERRAFORM_DIR:2}"
else
    # Already in correct format
    DOCKER_VOLUME="$TERRAFORM_DIR"
fi

echo "📂 Terraform directory: $TERRAFORM_DIR"
echo "🐋 Docker volume mount: $DOCKER_VOLUME"

# Build the layer using Docker with Python 3.12 on Linux AMD64
docker run --rm \
  --platform linux/amd64 \
  -v "$DOCKER_VOLUME":/output \
  python:3.12-slim \
  bash -c "
    set -e
    echo '📦 Installing Pillow for Linux AMD64...' && \
    pip install --quiet Pillow==10.4.0 -t /tmp/python/lib/python3.12/site-packages/ && \
    cd /tmp && \
    echo '📦 Creating layer zip file...' && \
    apt-get update -qq && apt-get install -y -qq zip > /dev/null 2>&1 && \
    zip -q -r pillow_layer.zip python/ && \
    ls -lh pillow_layer.zip && \
    cp pillow_layer.zip /output/ && \
    echo '✅ Layer built successfully for Linux (Lambda-compatible)!'
  " || {
    echo "❌ Docker build failed!"
    exit 1
  }

# Verify the file was created and has content
if [ ! -f "$TERRAFORM_DIR/pillow_layer.zip" ]; then
    echo "❌ Error: pillow_layer.zip was not created!"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$TERRAFORM_DIR/pillow_layer.zip" 2>/dev/null || stat -f%z "$TERRAFORM_DIR/pillow_layer.zip" 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -lt 1000 ]; then
    echo "❌ Error: pillow_layer.zip is too small ($FILE_SIZE bytes). Build may have failed."
    exit 1
fi

echo "📍 Location: $TERRAFORM_DIR/pillow_layer.zip"
echo "📦 Size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE 2>/dev/null || echo "$FILE_SIZE bytes")"
echo "✅ Layer is now compatible with AWS Lambda on all platforms!"