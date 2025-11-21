# Kamal & CircleCI Deployment Troubleshooting Guide

This document logs the issues encountered while setting up a Kamal deployment pipeline on CircleCI targeting an AWS EC2 instance, along with their solutions.

## 1. SSH & Connectivity

### Issue: Securely using SSH Keys in CI
**Problem:** CircleCI needs the private SSH key (`.pem`) to connect to EC2, but storing it as plain text is insecure, and CircleCI environment variables have size/formatting limits for multiline strings.
**Solution:**
1.  **Encrypt Locally:** Encrypt the PEM file using OpenSSL and encode it in Base64 to make it a single string.
    ```bash
    openssl enc -aes-256-cbc -pbkdf2 -salt -in ~/.ssh/your-key.pem -out encrypted-key.enc -k "$ENCRYPTION_KEY"
    base64 -i encrypted-key.enc > encoded_key.txt # macOS (-i), Linux usually no flag or -w0
    ```
2.  **Store in CI:** Save the content of `encoded_key.txt` as `ENCRYPTED_SSH_KEY` and the password as `ENCRYPTION_KEY` in CircleCI Project Settings.
3.  **Decrypt in Pipeline:**
    ```yaml
    - run:
        name: Decrypt SSH key
        command: |
          echo "$ENCRYPTED_SSH_KEY" | base64 -d | \
            openssl enc -aes-256-cbc -d -pbkdf2 -k "$ENCRYPTION_KEY" \
            > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
    ```

### Issue: SSH Permission Denied (User)
**Problem:** `Please login as the user "ec2-user" rather than the user "root".`
**Solution:** Kamal defaults to `root`. For AWS Amazon Linux, you must specify `ec2-user`.
*   **Fix:** In `config/deploy.yml`:
    ```yaml
    ssh:
      user: ec2-user
    ```

## 2. Docker & EC2 Setup

### Issue: Docker Missing on EC2
**Problem:** `bash: line 1: docker: command not found` when Kamal connects.
**Solution:** Install Docker on the EC2 instance manually or via user data script.
```bash
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
# Logout and login again for group changes to take effect
```

### Issue: CircleCI Remote Docker Version
**Problem:** `Job was rejected because this version of Docker is not supported`.
**Solution:** In `.circleci/config.yml`, use a compatible version or let CircleCI choose the default.
```yaml
- setup_remote_docker:
    version: 20.10.24 # or remove version line entirely
```

## 3. Build & Push (BuildKit)

### Issue: BuildKit Session Errors
**Problem:** `rpc error: code = Unknown desc = no http response from session` during `kamal deploy` (which tries to stream the build context).
**Solution:** **Separate the Build Step.** Instead of letting Kamal build, build manually in CI and push to the registry, then tell Kamal to deploy existing images.
1.  **CI Step:**
    ```yaml
    docker build -t user/repo:$SHA -t user/repo:latest --label service="my-service" .
    docker push user/repo:$SHA
    docker push user/repo:latest
    ```
2.  **Kamal Step:**
    ```bash
    kamal deploy --skip-push --version $SHA
    ```
    *Note:* You MUST add `--label service="service_name"` to the docker build command, otherwise Kamal won't recognize the image.

### Issue: Docker Hub Permissions
**Problem:** `unauthorized: access token has insufficient scopes`.
**Solution:** Generate a new Docker Hub Access Token with **Read, Write, Delete** permissions.

## 4. Application Configuration

### Issue: Puma "Address already in use"
**Problem:** `Address already in use - bind(2) for "0.0.0.0" port 3000`.
**Cause:** `config/puma.rb` had both `port ENV...` and `bind "tcp://..."`. `port` is an alias for `bind`, so it tried to bind twice.
**Solution:** Use only one. Preferred for Docker:
```ruby
# config/puma.rb
bind "tcp://0.0.0.0:#{ENV.fetch("PORT") { 3000 }}"
# remove 'port ...'
```

### Issue: Database Connection (Docker Networking)
**Problem:** `ActiveRecord::DatabaseConnectionError ... hostname: db`.
**Cause:** The Rails app runs in a container, but the DB (Kamal Accessory) runs in a separate container mapped to the *host's* port. They are not on the same internal Docker network by default, so `db` hostname doesn't resolve.
**Solution:** Connect to the **Docker Bridge Gateway IP** to access the host's mapped ports from inside the container.
*   **Linux/EC2:** The gateway is usually `172.17.0.1`.
*   **Fix:** In `config/deploy.yml`:
    ```yaml
    env:
      clear:
        DATABASE_HOST: 172.17.0.1
    ```

### Issue: Zeitwerk NameError (Crash Loop)
**Problem:** App container starts but exits immediately. Logs show `Zeitwerk::NameError: expected file ... to define constant ...`.
**Cause:** A file exists in the wrong place or with the wrong name (e.g., `app/models/OrdersControllerDecorater.rb` instead of `app/controllers/orders_controller_decorator.rb`).
**Solution:** Delete the file or fix the naming/location to match Rails conventions.

## 5. Miscellaneous

### Issue: CircleCI YAML Syntax
**Problem:** `Unclosed '<<' tag`.
**Cause:** Using heredocs (`<<EOF`) inside CircleCI YAML can be tricky due to YAML parsing.
**Solution:** Use `printf` or standard `echo` commands instead of complex heredocs in the `config.yml`.

### Issue: Missing Kamal Environment
**Problem:** `docker: open .kamal/env/roles/...: no such file or directory`.
**Cause:** `kamal deploy` assumes environment files exist.
**Solution:** Run `kamal env push` explicitly in the CI pipeline before deploying.

### Issue: Traefik Port Conflicts
**Problem:** Traefik fails to start because port 80 is taken.
**Cause:** `httpd` or `nginx` pre-installed on the AMI.
**Solution:** Stop/Disable them:
```bash
sudo systemctl stop httpd
sudo systemctl disable httpd
```

