# Checking Frontend Environment Variables

To check if `process.env.API_URL` is being read correctly in your frontend container:

## Method 1: Check Container Logs
After the frontend container starts, check its logs:
```bash
kamal accessory logs storefront
```

Look for any console.log statements that print `process.env.API_URL` or `API_URL`.

## Method 2: Exec into Container and Check
```bash
# SSH into your server
ssh -i ~/.ssh/kamal-deploy-key.pem ec2-user@13.53.125.253

# Find the container
docker ps | grep storefront

# Exec into the container
docker exec -it <container_id> sh

# Check environment variables
echo $API_URL
# or
env | grep API_URL
```

## Method 3: Add Debug Logging in Frontend Code
If you have access to the frontend codebase, add this to your Next.js app:

```javascript
// In your frontend code (e.g., pages/_app.js or app/layout.js)
console.log('API_URL from env:', process.env.API_URL);
console.log('All env vars:', process.env);
```

Then rebuild and redeploy the frontend Docker image.

## Current Configuration
- **API_URL**: `http://13.53.125.253:3001`
- **Frontend Port**: `3000` (internal)
- **Frontend Access**: `http://13.53.125.253/` (via Traefik)
- **Backend Access**: `http://13.53.125.253:3001` (direct port)



