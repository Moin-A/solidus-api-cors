# Root Causes: Unhealthy Containers During Kamal Deployment

This document summarizes the **root causes** we discovered when Kamal deployments failed due to unhealthy containers.

## 1. Missing Assets in Docker Image

### Root Cause
**`.dockerignore` was excluding `app/assets/builds/*`**, so even though `tailwind.css` files were committed to git, Docker wasn't copying them into the image during build.

### Symptoms
- Container starts but returns 500 errors
- Logs show: `ActionView::Template::Error (couldn't find file 'tailwind.css')`
- Admin panel fails to load

### Fix
```dockerfile
# .dockerignore - Added exceptions
/app/assets/builds/*
!/app/assets/builds/.keep
!/app/assets/builds/tailwind.css
!/app/assets/builds/solidus_admin/
!/app/assets/builds/solidus_admin/tailwind.css
```

### Lesson
**Always verify `.dockerignore` doesn't exclude files your app needs at runtime.**

---

## 2. Missing JavaScript Runtime

### Root Cause
**Docker image didn't have Node.js installed**, but `config.assets.compile = true` in production requires a JavaScript runtime to compile assets on-the-fly.

### Symptoms
- Container starts but crashes when rendering views
- Logs show: `ActionView::Template::Error (Could not find a JavaScript runtime)`
- Any page that needs asset compilation fails

### Fix
```dockerfile
# Dockerfile - Added Node.js
RUN apt-get install --no-install-recommends -y curl libvips postgresql-client nodejs
```

### Lesson
**If you enable runtime asset compilation, you need a JS runtime in the container.**

---

## 3. Missing Asset Declarations in Production

### Root Cause
**Solidus gem assets weren't declared in `manifest.js` and `assets.rb` precompile list**. Rails requires explicit declarations for production.

### Symptoms
- Container starts but returns 500 errors
- Logs show: `Asset 'spree/backend/themes/solidus_admin.css' was not declared to be precompiled`
- Admin panel fails to load

### Fix
```javascript
// app/assets/config/manifest.js
//= link spree/backend/themes/solidus_admin.css
//= link spree/backend/all.js
```

```ruby
# config/initializers/assets.rb
Rails.application.config.assets.precompile += ['spree/backend/themes/solidus_admin.css']
Rails.application.config.assets.precompile += ['spree/backend/all.js']
```

### Lesson
**Gem assets must be explicitly declared in both `manifest.js` AND `assets.rb` for production.**

---

## 4. Database Connection: Wrong Host Configuration

### Root Cause
**App container tried to connect to `db` hostname**, but Kamal accessories run on the host's ports, not in the same Docker network. The hostname `db` doesn't resolve.

### Symptoms
- Container starts but health checks fail
- Logs show: `ActiveRecord::DatabaseConnectionError: There is an issue connecting with your hostname: db`
- App can't connect to PostgreSQL

### Fix
```yaml
# config/deploy.yml
env:
  clear:
    DATABASE_HOST: 172.17.0.1  # Docker bridge gateway IP
```

### Lesson
**When containers need to reach host-mapped ports, use the Docker bridge gateway IP (`172.17.0.1` on Linux), not service names.**

---

## 5. Puma Port Double Binding

### Root Cause
**Both `port` and `bind` were configured in `puma.rb`**. Since `port` is an alias for `bind`, Puma tried to bind to port 3000 twice.

### Symptoms
- Container starts but immediately exits
- Logs show: `Address already in use - bind(2) for "0.0.0.0" port 3000`
- Health checks fail

### Fix
```ruby
# config/puma.rb - Use only bind
bind "tcp://0.0.0.0:#{ENV.fetch("PORT") { 3001 }}"
# Remove: port ENV.fetch("PORT") { 3001 }
```

### Lesson
**Use either `port` OR `bind`, not both. For Docker, prefer `bind` with explicit interface.**

---

## 6. SSL Redirect Loop

### Root Cause
**`config.force_ssl = true`** in production while Traefik was serving HTTP (not HTTPS), causing infinite redirects.

### Symptoms
- Container is healthy but requests fail
- Browser shows redirect loops
- `curl` shows: `HTTP/1.1 301 Moved Permanently` redirecting to HTTPS

### Fix
```ruby
# config/environments/production.rb
config.force_ssl = false  # Until SSL is properly configured
```

### Lesson
**Don't force SSL until your proxy (Traefik/load balancer) is configured for HTTPS.**

---

## 7. Missing Environment Variables

### Root Cause
**Critical environment variables weren't set in CircleCI**, causing the app to fail during initialization.

### Symptoms
- Container starts but crashes immediately
- Logs show: `KeyError: key not found: "RAILS_MASTER_KEY"`
- Or: `ArgumentError: key must be 16 bytes` (wrong key format)

### Fix
- Set `RAILS_MASTER_KEY` in CircleCI (must be 32 hex characters for Rails 7)
- Set `POSTGRES_PASSWORD` in CircleCI
- Set `SECRET_KEY_BASE` in CircleCI
- Ensure `.kamal/secrets` references them correctly

### Lesson
**Always verify all required environment variables are set in CI/CD before deployment.**

---

## 8. Zeitwerk Autoloading Errors

### Root Cause
**File naming/location didn't match Rails conventions**, causing Zeitwerk to fail during autoloading.

### Symptoms
- Container crashes on startup
- Logs show: `Zeitwerk::NameError: expected file ... to define constant ...`
- App never becomes healthy

### Fix
- Rename files to match class/module names exactly
- Move files to correct directories
- Or ignore decorator files in `config/application.rb`:
  ```ruby
  Rails.autoloaders.main.ignore(Rails.root.join('app/**/*_decorator*.rb'))
  ```

### Lesson
**Rails autoloading is strict. File names must match constant names exactly.**

---

## 9. Traefik Not Running

### Root Cause
**Traefik container wasn't started**, so no routing was happening even though app containers were healthy. Also, **port 80 was blocked by `httpd` or `nginx`** pre-installed on the EC2 AMI.

### Symptoms
- Containers are healthy but requests fail
- `curl localhost` returns connection refused
- No Traefik container in `docker ps`
- Or Traefik fails to start: `Error response from daemon: driver failed programming external connectivity`

### Fix

**Step 1: Stop conflicting services on EC2**
```bash
# SSH into EC2
ssh -i ~/.ssh/kamal-deploy-key.pem ec2-user@13.53.125.253

# Stop and disable httpd/nginx
sudo systemctl stop httpd
sudo systemctl stop nginx
sudo systemctl disable httpd
sudo systemctl disable nginx
```

**Step 2: Add to CircleCI pipeline (automatic fix)**
```yaml
# .circleci/config.yml - Step 7: Prepare EC2
- run:
    name: Prepare EC2
    command: |
       ssh -i ~/.ssh/kamal-deploy-key.pem -o ConnectTimeout=10 ec2-user@$EC2_IP \
         "sudo systemctl stop httpd || true && sudo systemctl stop nginx || true"
```

**Step 3: Manually start Traefik once (if needed)**
```bash
# On EC2, manually start Traefik to pull image and initialize
docker run -d --name traefik \
  -p 80:80 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  traefik:v2.10
```

**Step 4: Kamal will manage Traefik automatically**
After the first manual start, Kamal's `proxy` configuration in `deploy.yml` will automatically manage Traefik on subsequent deployments.

### Lesson
**Always stop conflicting services (httpd/nginx) before deploying. Kamal manages Traefik, but it needs port 80 to be free.**

---

## 10. Docker Daemon Not Running on EC2

### Root Cause
**Docker service wasn't started on the EC2 instance**, so Kamal couldn't run any Docker commands. Also, **`ec2-user` didn't have permissions** to access Docker socket.

### Symptoms
- Deployment fails immediately
- Logs show: `Cannot connect to the Docker daemon at unix:///var/run/docker.sock`
- Or: `ERROR: failed to initialize builder ... Is the docker daemon running?`
- `docker ps` fails on EC2 with permission denied

### Fix

**Step 1: Install Docker (if not installed)**
```bash
# SSH into EC2
ssh -i ~/.ssh/kamal-deploy-key.pem ec2-user@13.53.125.253

# Install Docker
sudo yum update -y
sudo yum install -y docker
```

**Step 2: Start and enable Docker service**
```bash
# Start Docker daemon
sudo systemctl start docker
sudo systemctl enable docker  # Start on boot
```

**Step 3: Add ec2-user to docker group**
```bash
# Give ec2-user permission to run Docker commands
sudo usermod -aG docker ec2-user

# Fix socket permissions (if needed)
sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock
```

**Step 4: Verify Docker is working**
```bash
# Logout and login again for group changes, or use newgrp
newgrp docker

# Test Docker
docker ps
docker run hello-world
```

**Alternative: Use EC2 User Data Script (for new instances)**
```bash
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user
```

### Lesson
**Docker must be installed, running, and the deployment user must be in the `docker` group. Always verify with `docker ps` before deploying.**

---

## Summary: Most Common Root Causes

1. **Missing files in Docker image** (`.dockerignore` too aggressive)
2. **Missing runtime dependencies** (Node.js for asset compilation)
3. **Missing asset declarations** (gem assets not in manifest/precompile)
4. **Network misconfiguration** (wrong host for database/Redis)
5. **Port binding conflicts** (double binding in Puma)
6. **SSL/HTTPS misconfiguration** (force_ssl without proper setup)
7. **Missing environment variables** (secrets not set in CI/CD)
8. **Rails autoloading errors** (file naming conventions)
9. **Infrastructure not running** (Traefik, Docker daemon)

## Debugging Strategy

When a container is unhealthy:

1. **Check container logs**: `docker logs <container_id>`
2. **Check health endpoint**: `curl http://localhost:3001/up`
3. **Manually run the image**: `docker run --env-file .kamal/env/roles/app-web.env <image>`
4. **Verify environment variables**: `docker exec <container_id> env`
5. **Test database connectivity**: `docker exec <container_id> rails db:version`
6. **Check for missing files**: `docker exec <container_id> ls -la /rails/app/assets/builds/`

