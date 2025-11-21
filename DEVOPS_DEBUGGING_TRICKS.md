# DevOps Debugging Tricks & Commands

This guide documents powerful debugging techniques and commands used to troubleshoot deployments on AWS EC2, specifically for Kamal/Docker environments.

## 1. Connecting to the Server

### Basic SSH Connection
Connect to your EC2 instance using your private key.
```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2_IP>
```

### Secure SSH Key Handling in CI (CircleCI)
Instead of storing the key as a plain string, encrypt it locally and decrypt it in the pipeline.
1.  **Encrypt (Local):**
    ```bash
    openssl enc -aes-256-cbc -pbkdf2 -salt -in key.pem -out encrypted.enc -k "SECRET"
    base64 -i encrypted.enc # Copy this string to CI env var
    ```
2.  **Decrypt (CI):**
    ```bash
    echo "$ENCRYPTED_SSH_KEY" | base64 -d | openssl enc -aes-256-cbc -d -pbkdf2 -k "$ENCRYPTION_KEY" > ~/.ssh/id_rsa
    ```

---

## 2. Container & Application Debugging

### Check Running Containers
See what is actually running on the server.
```bash
docker ps -a
# Shows container ID, Image, Status (Up/Exited), and Names
```

### Get Container Logs
View the logs of a specific container to see startup errors or runtime exceptions.
```bash
# By Name (e.g., traefik)
docker logs traefik --tail 50

# By ID (find ID from docker ps)
docker logs <container_id> --tail 100
```

### Manually Run the App Image (The "Golden" Trick)
If Kamal fails to start the app, run the image manually on the server to see the exact error message immediately.
1.  **Find the image tag:**
    ```bash
    docker images | grep your-app-name
    ```
2.  **Run it (Simulating Kamal):**
    Use `--env-file` to load secrets Kamal pushed, and `-e` to override vars.
    ```bash
    docker run --rm \
      --env-file .kamal/env/roles/your-app-web.env \
      -e DATABASE_HOST=172.17.0.1 \
      -e RAILS_ENV=production \
      your-username/your-app:tag
    ```
    *   `--rm`: Automatically remove the container when it exits.
    *   `--env-file`: Loads the secret env vars file created by `kamal env push`.

### Inspect Environment Variables
Check what environment variables are actually set inside the container.
```bash
docker exec <container_id> env
```

---

## 3. Network & Connectivity Debugging

### Check Listening Ports (Host)
Verify if a process (like Traefik or Puma) is actually listening on a port.
```bash
sudo lsof -i :80
sudo lsof -i :3000
```
*   If nothing shows up, the service isn't running or bound to that port.

### Verify Docker Bridge Gateway IP
When connecting containers (App -> DB) via the host, you need the gateway IP.
```bash
docker network inspect bridge | grep Gateway
# Usually "172.17.0.1" on Linux
```

### Test Internal Routing (Local Curl)
Verify if the web server (Traefik) is responding locally, bypassing firewalls/security groups.
```bash
curl -v http://localhost
```
*   **301 Moved Permanently**: Often means HTTP -> HTTPS redirection.
*   **Connection Refused**: Nothing listening on port 80.
*   **404 Not Found**: Server is running but doesn't recognize the Host header.

---

## 4. Database Connectivity

### Test Database Connection from Shell
If the app can't connect to the DB, test if *you* can connect from the server using a temporary container.
```bash
docker run --rm postgres:15 psql \
  -h 172.17.0.1 \
  -p 5432 \
  -U your_db_user \
  -d your_db_name \
  -c 'SELECT 1;'
```
*   If this fails, it's a network/firewall/config issue.
*   If this works, the issue is inside your application configuration.

---

## 5. Common Fixes

### Fix "Address already in use - bind(2)"
*   **Cause:** Puma configured to bind port 3000 twice (once via `port`, once via `bind`).
*   **Fix:** Use only `bind "tcp://0.0.0.0:3000"` in `config/puma.rb`.

### Fix "Connection Refused" (Docker Networking)
*   **Cause:** App container trying to connect to `localhost` or `db` hostname, which doesn't exist in its network.
*   **Fix:** Use the **Docker Bridge Gateway IP** (e.g., `172.17.0.1`) to reach services mapped to the host's ports.

### Fix "Zeitwerk::NameError"
*   **Cause:** A file defines a constant that doesn't match its filename (Rails autoloading rules).
*   **Fix:** Rename the file to match the class/module exactly (e.g., `OrdersControllerDecorator` -> `orders_controller_decorator.rb`).

### Fix Infinite Redirect Loops
*   **Cause:** `config.force_ssl = true` in Rails while running behind a proxy (Traefik) without SSL.
*   **Fix:** Set `config.force_ssl = false` in `config/environments/production.rb` until SSL is properly configured.



