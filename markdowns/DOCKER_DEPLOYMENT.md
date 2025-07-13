# SyntaxRAG Docker Deployment Guide

This guide explains how to deploy and ship the SyntaxRAG recall agent system using Docker containers.

## 🚀 Quick Start

### Option 1: Local Development
```bash
# Start with existing docker-compose
docker-compose up -d

# Or use the new production setup
cp env.example .env
# Edit .env with your settings
./deploy.sh
```

### Option 2: Production Deployment
```bash
# Deploy with all optimizations
./deploy.sh --production
```

### Option 3: Build and Ship
```bash
# Export as portable tar file
./ship.sh --tar

# Or push to Docker registry
./ship.sh --registry docker.io/yourusername
```

## 📦 Docker Files Overview

### Core Files
- **`Dockerfile`** - Multi-stage build for SyntaxRAG MCP server
- **`docker-compose.prod.yml`** - Production deployment with PostgreSQL
- **`.dockerignore`** - Optimized build context
- **`env.example`** - Environment configuration template

### Deployment Scripts
- **`deploy.sh`** - Automated deployment script
- **`ship.sh`** - Build and ship Docker images
- **`init_docker_db.sql`** - Database initialization (from previous setup)

## 🔧 Configuration

### Environment Variables
Copy `env.example` to `.env` and configure:

```bash
# Required
OPENAI_API_KEY=your_api_key_here

# Database (auto-configured in Docker)
POSTGRES_PASSWORD=agent_recall_password_change_me
POSTGRES_PORT=5433

# Server
SYNTAXRAG_PORT=8000
LOG_LEVEL=INFO

# Optional: Production settings
NGINX_PORT=80
LANGSMITH_TRACING_V2=true
```

### Docker Image Features
- **Optimized Build**: Multi-stage build with minimal final image
- **Security**: Non-root user, minimal attack surface
- **Health Checks**: Built-in health monitoring
- **Volume Mounts**: Persistent data and logs
- **Environment**: Production-ready configuration

## 🚢 Shipping Options

### 1. Docker Registry (Recommended)
```bash
# Build and push to Docker Hub
./ship.sh --registry docker.io/yourusername --tag v1.0

# Use on any machine
docker pull docker.io/yourusername/syntaxrag:v1.0
```

### 2. Tar Export (Air-gapped Deployment)
```bash
# Create portable deployment package
./ship.sh --tar

# Transfer syntaxrag-deployment-latest.tar.gz to target machine
# Extract and deploy
tar -xzf syntaxrag-deployment-latest.tar.gz
cd syntaxrag-deployment-temp
docker load < syntaxrag-docker-image.tar
./deploy.sh
```

### 3. Multi-platform Build
```bash
# Support both ARM and x86
./ship.sh --platforms linux/amd64,linux/arm64 --registry yourregistry
```

## 🏗️ Architecture

### Production Deployment
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Nginx       │────│  SyntaxRAG      │────│   PostgreSQL    │
│  (Port 80/443)  │    │    Server       │    │   + pgvector    │
│                 │    │  (Port 8000)    │    │   (Port 5432)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                        │                        │
        │                        │                        │
        └─── Load Balancer ───────┼─── Health Checks ─────┘
                                 │
                                 └─── Persistent Volumes
```

### Container Network
- **syntaxrag-network**: Private bridge network
- **Health Checks**: Automatic service monitoring
- **Volume Persistence**: Database and logs persist across restarts

## 📊 Monitoring

### Health Checks
```bash
# Check service health
curl http://localhost:8000/health

# View container status
docker-compose -f docker-compose.prod.yml ps

# Monitor logs
docker-compose -f docker-compose.prod.yml logs -f
```

### Metrics
```bash
# Container resource usage
docker stats

# Database statistics
docker exec syntaxrag-db psql -U postgres -d agent_recall -c "SELECT * FROM memory_stats;"
```

## 🔧 Maintenance

### Updates
```bash
# Rebuild and redeploy
./deploy.sh --no-cache

# Update specific service
docker-compose -f docker-compose.prod.yml up -d --no-deps syntaxrag-server
```

### Backup
```bash
# Backup database
docker exec syntaxrag-db pg_dump -U postgres agent_recall > backup.sql

# Backup volumes
docker run --rm -v syntaxrag-postgres-data:/data -v $(pwd):/backup alpine tar czf /backup/postgres-backup.tar.gz -C /data .
```

### Scaling
```bash
# Scale SyntaxRAG server (if load balancer configured)
docker-compose -f docker-compose.prod.yml up -d --scale syntaxrag-server=3
```

## 🐛 Troubleshooting

### Common Issues

**Container won't start:**
```bash
# Check logs
docker-compose -f docker-compose.prod.yml logs syntaxrag-server

# Check configuration
docker-compose -f docker-compose.prod.yml config
```

**Database connection issues:**
```bash
# Test database connectivity
docker exec syntaxrag-db pg_isready -U postgres

# Check database logs
docker-compose -f docker-compose.prod.yml logs postgres
```

**Health check failing:**
```bash
# Manual health check
curl -v http://localhost:8000/health

# Check container health
docker inspect syntaxrag-server | grep Health -A 10
```

### Performance Tuning
```bash
# Adjust container resources
docker-compose -f docker-compose.prod.yml up -d --scale syntaxrag-server=2

# Monitor resource usage
docker stats

# Optimize PostgreSQL settings in docker-compose.prod.yml
```

## 🔒 Security

### Production Security
- Non-root container user
- Minimal base image (Python slim)
- Environment variable secrets
- Network isolation
- Health check endpoints only

### Hardening
```bash
# Scan for vulnerabilities
docker scan syntaxrag:latest

# Update base images regularly
./deploy.sh --no-cache
```

## 📝 Deployment Checklist

- [ ] Configure `.env` file with valid API keys
- [ ] Test local deployment: `./deploy.sh`
- [ ] Build shipping package: `./ship.sh --tar`
- [ ] Test on target machine
- [ ] Set up monitoring and alerts
- [ ] Configure backup procedures
- [ ] Document access credentials
- [ ] Set up log rotation

## 🌐 Multi-Machine Deployment

### Registry Approach
```bash
# On build machine
./ship.sh --registry docker.io/company/syntaxrag --tag production

# On target machines
docker pull docker.io/company/syntaxrag:production
docker run -d --name syntaxrag -p 8000:8000 docker.io/company/syntaxrag:production
```

### Tar Approach
```bash
# On build machine
./ship.sh --tar

# Transfer syntaxrag-deployment-latest.tar.gz to target machines
# On each target machine
tar -xzf syntaxrag-deployment-latest.tar.gz
cd syntaxrag-deployment-temp
./deploy.sh
```

---

🚀 **Your SyntaxRAG recall agent is now ready for deployment across multiple machines!**

For additional support and updates, check the project repository and documentation.
