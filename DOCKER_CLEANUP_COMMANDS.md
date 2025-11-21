# Docker Cleanup Commands

## Quick Cleanup (All-in-One)

**⚠️ WARNING: This will remove ALL containers, images, volumes, and networks!**

```bash
# Stop all running containers, remove all containers, images, volumes, networks, and build cache
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker system prune -a --volumes -f
```

## Step-by-Step (Safer)

### 1. Stop All Running Containers
```bash
docker stop $(docker ps -q)
```

### 2. Remove All Containers (Stopped and Running)
```bash
docker rm $(docker ps -aq)
```

### 3. Prune Everything (Free Space)
```bash
# Remove all unused containers, networks, images (both dangling and unreferenced), and optionally, volumes
docker system prune -a --volumes -f
```

## Individual Prune Commands (More Control)

### Remove Only Stopped Containers
```bash
docker container prune -f
```

### Remove Unused Images
```bash
docker image prune -a -f
```

### Remove Unused Volumes
```bash
docker volume prune -f
```

### Remove Unused Networks
```bash
docker network prune -f
```

### Remove Build Cache
```bash
docker builder prune -a -f
```

## For EC2 (SSH Command)

If you want to run this on your EC2 instance:

```bash
ssh -i ~/.ssh/kamal-deploy-key.pem ec2-user@13.53.125.253 \
  "docker stop \$(docker ps -q) 2>/dev/null || true && \
   docker rm \$(docker ps -aq) 2>/dev/null || true && \
   docker system prune -a --volumes -f"
```

## What Each Command Does

- `docker stop $(docker ps -q)` - Stops all running containers
- `docker rm $(docker ps -aq)` - Removes all containers (running and stopped)
- `docker system prune -a --volumes -f`:
  - `-a` - Remove all unused images, not just dangling ones
  - `--volumes` - Remove unused volumes
  - `-f` - Force, don't prompt for confirmation

## Check Disk Space Before/After

```bash
# Before cleanup
df -h
docker system df

# After cleanup
df -h
docker system df
```

