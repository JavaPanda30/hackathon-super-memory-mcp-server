# SyntaxRAG Docker Shipping Guide

This guide explains how to build, ship, and deploy the SyntaxRAG Docker image across different machines.

## Quick Start

### 1. Build the Docker Image
```bash
# Build the image with a tag
docker build -t syntaxrag:latest .

# Or build with version tag
docker build -t syntaxrag:v1.0.0 .
```

### 2. Ship the Image

#### Option A: Docker Registry (Recommended)
```bash
# Tag for registry
docker tag syntaxrag:latest your-registry.com/syntaxrag:latest

# Push to registry
docker push your-registry.com/syntaxrag:latest

# On target machine, pull the image
docker pull your-registry.com/syntaxrag:latest
```

#### Option B: Save/Load Image File
```bash
# Save image to tar file
docker save syntaxrag:latest > syntaxrag-image.tar

# Transfer file to target machine, then load
docker load < syntaxrag-image.tar
```

### 3. Deploy on Target Machine
```bash
# Copy docker-compose.production.yml to target machine
scp docker-compose.production.yml user@target-machine:/path/to/deployment/

# Deploy
docker-compose -f docker-compose.production.yml up -d
```

## Detailed Instructions

### Building for Different Architectures

#### Multi-Architecture Build
```bash
# Setup buildx (one time)
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# Build for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag syntaxrag:multiarch \
  --push .
```

#### Specific Architecture
```bash
# For AMD64 (Intel/AMD)
docker build --platform linux/amd64 -t syntaxrag:amd64 .

# For ARM64 (Apple Silicon, ARM servers)
docker build --platform linux/arm64 -t syntaxrag:arm64 .
```

### Environment Configuration

#### 1. Copy Environment Template
```bash
cp .env.example .env
```

#### 2. Edit Configuration
Edit `.env` with your specific values:
```env
# Database
POSTGRES_PASSWORD=your_secure_password

# OpenAI
OPENAI_API_KEY=your_api_key_here

# Embedding configuration
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIMENSION=1536
```

### Deployment Options

#### Option 1: Docker Compose (Recommended)
```bash
# Development
docker-compose up -d

# Production
docker-compose -f docker-compose.production.yml up -d
```

#### Option 2: Docker Run
```bash
# Start database
docker run -d \
  --name syntaxrag-db \
  --env-file .env \
  -p 5433:5432 \
  -v syntaxrag_postgres:/var/lib/postgresql/data \
  pgvector/pgvector:pg16

# Start application
docker run -d \
  --name syntaxrag-app \
  --env-file .env \
  -p 8000:8000 \
  --link syntaxrag-db:postgres \
  syntaxrag:latest
```

#### Option 3: Kubernetes
```bash
# Create namespace
kubectl create namespace syntaxrag

# Apply configurations
kubectl apply -f k8s/ -n syntaxrag
```

### Registry Options

#### Docker Hub
```bash
# Login
docker login

# Tag and push
docker tag syntaxrag:latest username/syntaxrag:latest
docker push username/syntaxrag:latest

# Pull on target machine
docker pull username/syntaxrag:latest
```

#### GitHub Container Registry
```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Tag and push
docker tag syntaxrag:latest ghcr.io/username/syntaxrag:latest
docker push ghcr.io/username/syntaxrag:latest

# Pull on target machine
docker pull ghcr.io/username/syntaxrag:latest
```

#### AWS ECR
```bash
# Login (AWS CLI required)
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-west-2.amazonaws.com

# Tag and push
docker tag syntaxrag:latest 123456789012.dkr.ecr.us-west-2.amazonaws.com/syntaxrag:latest
docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/syntaxrag:latest
```

### Production Deployment

#### 1. Prepare Target Machine
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### 2. Transfer Files
```bash
# Copy deployment files
scp docker-compose.production.yml user@target:/opt/syntaxrag/
scp .env user@target:/opt/syntaxrag/
scp init_docker_db.sh user@target:/opt/syntaxrag/
scp init_docker_db.sql user@target:/opt/syntaxrag/
```

#### 3. Deploy
```bash
# On target machine
cd /opt/syntaxrag

# Initialize database
./init_docker_db.sh

# Start services
docker-compose -f docker-compose.production.yml up -d

# Check status
docker-compose -f docker-compose.production.yml ps
```

### Automated Deployment Script

Create `deploy.sh`:
```bash
#!/bin/bash
set -e

REGISTRY="your-registry.com"
IMAGE_NAME="syntaxrag"
VERSION=${1:-latest}
TARGET_HOST=${2:-"production-server"}

echo "🚀 Deploying SyntaxRAG $VERSION to $TARGET_HOST"

# Build and push image
echo "📦 Building image..."
docker build -t $REGISTRY/$IMAGE_NAME:$VERSION .
docker push $REGISTRY/$IMAGE_NAME:$VERSION

# Deploy to target
echo "🎯 Deploying to $TARGET_HOST..."
ssh $TARGET_HOST << EOF
  cd /opt/syntaxrag
  docker pull $REGISTRY/$IMAGE_NAME:$VERSION
  docker-compose -f docker-compose.production.yml down
  docker-compose -f docker-compose.production.yml up -d
  echo "✅ Deployment complete!"
EOF
```

### Health Checks and Monitoring

#### Check Service Health
```bash
# Check application health
curl http://localhost:8000/health

# Check container status
docker-compose ps

# View logs
docker-compose logs -f syntaxrag-app
docker-compose logs -f syntaxrag-db
```

#### Monitor Resources
```bash
# Container stats
docker stats

# System resources
docker system df

# Clean up unused resources
docker system prune -a
```

### Troubleshooting

#### Common Issues

1. **Port conflicts**
   ```bash
   # Check what's using the port
   lsof -i :8000
   lsof -i :5433
   ```

2. **Database connection issues**
   ```bash
   # Check database logs
   docker logs syntaxrag-db
   
   # Test connection
   docker exec -it syntaxrag-db psql -U postgres -d agent_recall
   ```

3. **Image pull issues**
   ```bash
   # Check Docker login
   docker info
   
   # Verify image exists
   docker images | grep syntaxrag
   ```

4. **Environment variable issues**
   ```bash
   # Check environment in container
   docker exec syntaxrag-app env | grep POSTGRES
   ```

### Security Considerations

#### Production Security
- Use non-root user in containers ✅ (already implemented)
- Use specific version tags, not `latest`
- Implement proper secret management
- Use TLS/SSL in production
- Regular security updates

#### Environment Security
```bash
# Set restrictive permissions on .env
chmod 600 .env

# Use Docker secrets for sensitive data
echo "my_secret_password" | docker secret create postgres_password -
```

### Performance Optimization

#### Image Size Optimization
- Multi-stage builds
- Minimal base images
- Remove unnecessary packages
- Optimize layer caching

#### Runtime Optimization
```yaml
# In docker-compose.yml
services:
  syntaxrag-app:
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'
```

### Backup and Recovery

#### Database Backup
```bash
# Create backup
docker exec syntaxrag-db pg_dump -U postgres agent_recall > backup.sql

# Restore backup
docker exec -i syntaxrag-db psql -U postgres agent_recall < backup.sql
```

#### Volume Backup
```bash
# Backup volume
docker run --rm -v syntaxrag_postgres:/data -v $(pwd):/backup alpine tar czf /backup/postgres-backup.tar.gz -C /data .

# Restore volume
docker run --rm -v syntaxrag_postgres:/data -v $(pwd):/backup alpine tar xzf /backup/postgres-backup.tar.gz -C /data
```

---

🚀 **Your SyntaxRAG application is now ready to ship and deploy anywhere!**
