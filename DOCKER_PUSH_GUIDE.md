# How to Push Your Rails App to Docker Hub

## Your Setup:
- **Docker Hub Username**: `moindev`
- **Image Name**: `moindev/solidus-api-cors`
- **Dockerfile**: ✅ Already exists

---

## Method 1: Manual Build & Push (For Testing)

### Step 1: Login to Docker Hub
```bash
docker login -u moindev
# Enter your Docker Hub password or access token when prompted
```

### Step 2: Build the Docker Image
```bash
# From your project root directory
docker build -t moindev/solidus-api-cors .
```

### Step 3: Tag the Image (Optional - for versioning)
```bash
# Tag with a version
docker tag moindev/solidus-api-cors moindev/solidus-api-cors:v1.0.0

# Or tag with "latest"
docker tag moindev/solidus-api-cors moindev/solidus-api-cors:latest
```

### Step 4: Push to Docker Hub
```bash
# Push the image
docker push moindev/solidus-api-cors

# Or push a specific tag
docker push moindev/solidus-api-cors:latest
```

### Step 5: Verify on Docker Hub
Visit: https://hub.docker.com/r/moindev/solidus-api-cors

---

## Method 2: Automatic with Kamal (Recommended)

**Kamal does this automatically!** When you run `kamal deploy`, it will:

1. ✅ Build the Docker image from your Dockerfile
2. ✅ Tag it with your image name (`moindev/solidus-api-cors`)
3. ✅ Push it to Docker Hub (using `KAMAL_REGISTRY_PASSWORD`)
4. ✅ Pull it on EC2 and deploy

### Just run:
```bash
kamal deploy
```

**That's it!** Kamal handles everything.

---

## Method 3: CircleCI Automatic (Production)

When you push to `main` branch, CircleCI will:

1. Checkout your code
2. Run `kamal deploy`
3. Kamal builds and pushes automatically
4. Deploys to EC2

**No manual steps needed!**

---

## Quick Test Commands

### Test locally:
```bash
# Build
docker build -t moindev/solidus-api-cors .

# Test run locally
docker run -p 3000:3000 moindev/solidus-api-cors

# Login and push
docker login -u moindev
docker push moindev/solidus-api-cors
```

### Test with Kamal:
```bash
# This will build, push, and deploy
kamal deploy
```

---

## Troubleshooting

### "denied: requested access to the resource is denied"
- Make sure you're logged in: `docker login -u moindev`
- Check your Docker Hub access token has push permissions

### "Cannot connect to Docker daemon"
- Make sure Docker Desktop is running (on Mac/Windows)
- Or Docker service is running (on Linux)

### "Image not found" during Kamal deploy
- Make sure the image was pushed: `docker push moindev/solidus-api-cors`
- Check Docker Hub: https://hub.docker.com/r/moindev/solidus-api-cors

