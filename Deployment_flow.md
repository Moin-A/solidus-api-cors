# Blinker Rails API - Deployment Flow Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Dev Environment Deployment](#dev-environment-deployment)
4. [Production Environment Deployment](#production-environment-deployment)
5. [Feature Environment Deployment](#feature-environment-deployment)
6. [Docker Image Build Process](#docker-image-build-process)
7. [Database Migrations](#database-migrations)
8. [Environment Variables Management](#environment-variables-management)
9. [Detailed Script Analysis](#detailed-script-analysis)

---

## Overview

The Blinker Rails API uses a sophisticated CI/CD pipeline that combines:
- **CircleCI** for continuous integration and deployment orchestration
- **Docker** for containerization
- **Amazon EKS (Kubernetes)** for container orchestration
- **Terraform/Terragrunt** for infrastructure as code
- **AWS ECR** for Docker image registry
- **KMS encryption** for secrets management (via `gruntkms`)

---

## Architecture

### Key Components
1. **CircleCI**: Orchestrates build, test, and deploy pipeline
2. **Docker Base Image**: Cached layer with Ruby + dependencies
3. **Docker Application Image**: Base + application code
4. **AWS ECR**: Stores Docker images
5. **Kubernetes (EKS)**: Runs containers in pods
6. **Terragrunt**: Manages infrastructure state

### Environment Mapping
- `da/develop` branch → **dev** environment
- `da/stage` branch → **stage** environment
- `release-*` tag → **production** environment
- `feature/*` branch → **feature-[name]** environment (in dev cluster)

---

## Dev Environment Deployment

### Trigger
- Push to `da/develop` branch

### Step-by-Step Flow

#### 1. CircleCI Job Triggered
```bash
# Workflow: test-build-deploy
# Jobs run in sequence:
- validate-branch-name
- rubocop
- refresh-base-image (parallel with run-tests)
- run-tests (parallel with refresh-base-image)
- deploy (requires: run-tests, refresh-base-image)
```

#### 2. Validate Branch Name
```bash
# Job: validate-branch-name
# Ensures feature branches only contain alphanumeric and dashes
if [[ $CIRCLE_BRANCH =~ ^feature/ ]]; then
  export FEATURE_NAME=$( echo ${CIRCLE_BRANCH} | sed -e 's/.*\///g' )
  [[ $FEATURE_NAME =~ ^[a-zA-Z0-9-]+$ ]] || exit 1
fi
```

#### 3. Run Rubocop
```bash
# Job: rubocop
# Lints Ruby code
apt-get install -y build-essential cmake nodejs pdftk
gem install bundler -v $(cat Gemfile.lock | grep . | tail -1 | grep -Eo "[0-9\.]+")
bundle install --jobs 4 --retry 3
bundle exec rubocop --no-parallel
```

#### 4. Refresh Base Image
```bash
# Job: refresh-base-image
# Script: build_base.sh

# Calculate dependency checksum
export DEPENDENCY_CHECKSUM=$(cat Gemfile Gemfile.lock Dockerfile.base | sha1sum | awk '{print $1}')

# For dev branch: include dev/test gems
export BASE_IMAGE_NAME=${ECR_BASE}/rails-api:base-dev-${DEPENDENCY_CHECKSUM}

# Authenticate with ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin https://$ECR_BASE

# Try to pull existing image, or build new one
docker pull $BASE_IMAGE_NAME || ./build_base.sh

# Build base image (Dockerfile.base)
cat Dockerfile.base | \
    grep -v remove-for-dev | \
    docker build -t ${BASE_IMAGE_NAME} \
                 --build-arg GITHUB_OAUTH_TOKEN=$GITHUB_OAUTH_TOKEN \
                 -f- .

# Push to ECR
docker push $BASE_IMAGE_NAME

# For da/develop branch, also tag as latest
if [[ $CIRCLE_BRANCH == "da/develop" ]]; then
  docker tag $BASE_IMAGE_NAME $LATEST
  docker push $LATEST
fi
```

**Dockerfile.base Contents:**
```dockerfile
FROM ruby:3.1.4

# Install system dependencies
apt-get install -y build-essential curl nodejs pdftk wkhtmltopdf xvfb

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
cd /tmp && unzip awscliv2.zip && /tmp/aws/install

# Install gruntkms for KMS decryption
curl -Ls https://raw.githubusercontent.com/gruntwork-io/gruntwork-installer/master/bootstrap-gruntwork-installer.sh | \
  bash /dev/stdin --version "$GRUNTWORK_INSTALLER_VERSION"
gruntwork-install --repo "https://github.com/blinkergit/gruntkms" \
                  --binary-name "gruntkms" \
                  --tag "$GRUNTKMS_VERSION"

# Install gems
bundle config github.com $GITHUB_OAUTH_TOKEN:x-oauth-basic
bundle config set --local deployment 'true'          # removed for dev
bundle config set --local without 'development test' # removed for dev
bundle install --jobs 3 --retry 3
```

#### 5. Run Tests
```bash
# Job: run-tests (parallelism: 8)
# Uses CircleCI test splitting

# Setup PostgreSQL and Redis containers
docker:
  - image: ruby:3.1.4
  - image: cimg/postgres:9.6
  - image: redis:6

# Install dependencies
apt-get install -y build-essential cmake nodejs pdftk wkhtmltopdf
gem install bundler
bundle install --jobs 4 --retry 3

# Setup database
cp config/database.yml.circle config/database.yml
RAILS_ENV=test bundle exec rake db:schema:load --trace

# Run tests (split across 8 containers)
bundle exec rspec \
  --format RspecJunitFormatter \
  --out test_results/rspec.xml \
  --format progress \
  --color \
  $(circleci tests glob "spec/**/*_spec.rb" | circleci tests split --split-by=timings)
```

#### 6. Deploy Job
```bash
# Job: deploy
# Script: .circleci/deploy.sh

# Set environment variables
source <(.circleci/set_env.sh dev)

# Output:
export AWS_ACCOUNT_ID=392216643236
export AWS_REGION=us-west-2
export DEPENDENCY_CHECKSUM=<sha1sum>
export DOCKER_IMAGE=004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api
export DOCKER_REGISTRY=004671295794.dkr.ecr.us-west-2.amazonaws.com
export EKS_CLUSTER_ARN=arn:aws:eks:us-west-2:392216643236:cluster/eks-dev
export SERVICE_NAME=rails-api
export VPC_NAME=dev
export VPC_PREFIX=dev
export BASE_IMAGE_NAME=004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:base-<checksum>
export DOCKER_TAG=<CIRCLE_SHA1>

# Authenticate with ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin https://$DOCKER_REGISTRY

# Build Docker image
build-docker-image \
  --docker-image-name "$DOCKER_IMAGE" \
  --docker-image-tag "$DOCKER_TAG" \
  --build-arg BASE_IMAGE_NAME="$BASE_IMAGE_NAME" \
  --build-arg DOCKER_TAG="$DOCKER_TAG" \
  --build-arg GITHUB_OAUTH_TOKEN="$GITHUB_OAUTH_TOKEN" \
  --build-arg VPC_NAME="$VPC_NAME"
```

**Dockerfile Contents:**
```dockerfile
ARG BASE_IMAGE_NAME=blinker/api-base:latest
FROM ${BASE_IMAGE_NAME}

# Add application code
COPY . .

# Copy environment files
RUN mkdir /config
COPY config/*.env /config/

# Configure app
RUN cd /var/www/blinker/config && rm -f database.yml && mv database.docker.yml database.yml
RUN cd /var/www/blinker/config && rm -f unicorn.rb && ln -s unicorn.rb.sample unicorn.rb

# Expose ports
EXPOSE 8080 25658

# Entrypoint
CMD [ "bin/env" ]
```

#### 7. Update Infrastructure Repository
```bash
# Clone infrastructure-live repo
git clone git@github.com:BlinkerGit/infrastructure-live.git /tmp/infrastructure-live

# Update image version in Terragrunt configs
SERVICE_PATH="dev/us-west-2/dev/apps/rails-api"
CLOCKWORK_PATH="dev/us-west-2/dev/apps/clockwork"
SIDEKIQ_PATH="dev/us-west-2/dev/apps/sidekiq"

# Update each service
terraform-update-variable \
  --name "image_version" \
  --value "\"$DOCKER_TAG\"" \
  --vars-path "$CLOCKWORK_PATH/terragrunt.hcl" \
  --git-url "$INFRA_LIVE_REPO" \
  --git-checkout-path "/tmp/infrastructure-live" \
  --git-user-email "blinkerci@blinker.com" \
  --git-user-name "BlinkerCI"

# (Repeat for SIDEKIQ_PATH and SERVICE_PATH)
```

#### 8. Assume AWS Role & Configure Kubernetes
```bash
# Assume auto-deploy role
source <(assume_role.sh $AWS_ACCOUNT_ID)

# Configure access to EKS cluster
kubergrunt eks configure --eks-cluster-arn $EKS_CLUSTER_ARN
```

#### 9. Deploy to Kubernetes
```bash
# Apply Terragrunt configurations
terragrunt apply \
  --terragrunt-working-dir "/tmp/infrastructure-live/$CLOCKWORK_PATH" \
  -input=false \
  -auto-approve

terragrunt apply \
  --terragrunt-working-dir "/tmp/infrastructure-live/$SIDEKIQ_PATH" \
  -input=false \
  -auto-approve

terragrunt apply \
  --terragrunt-working-dir "/tmp/infrastructure-live/$SERVICE_PATH" \
  -input=false \
  -auto-approve
```

#### 10. Container Startup
When the Kubernetes pod starts, it runs:

```bash
# Script: bin/env
# Decrypts environment variables from /config/dev.env

# Read VPC_NAME from Kubernetes env
encrypted_config_contents=$(cat "/config/$VPC_NAME.env")

# Decrypt using gruntkms
decrypted_config=$(gruntkms decrypt --aws-region "$AWS_REGION" --ciphertext "$encrypted_config_contents")

# Create named pipe for secure env loading
mkfifo /tmp/.envrc
(echo -e "$decrypted_config" > /tmp/.envrc && rm -f /tmp/.envrc) &

# Read env vars from pipe
while read -r key val; do
  export $key="$val"
done < /tmp/.envrc

# Start application
bundle exec ruby script/entrypoint.rb $FLAVOR
```

```bash
# Script: script/entrypoint.rb
# SERVER_FLAVOR determines what to run

case SERVER_FLAVOR
when "server"
  bundle exec unicorn
when "worker"
  bundle exec sidekiq -v -C ./config/sidekiq.yml
when "scheduler"
  bundle exec clockwork ./config/schedule.rb
end

# For "server" flavor, also runs migrations:
if SERVER_FLAVOR == "server"
  # Check if database exists
  unless database_exists?
    bundle exec rake db:create
  end
  
  # Run migrations and seed
  bundle exec rake db:migrate db:grant
  bundle exec rake db:seed:integration
fi
```

---

## Production Environment Deployment

### Trigger
- Git tag matching `release-*` pattern (e.g., `release-v1.2.3`)

### Differences from Dev

#### 1. Set Environment Variables
```bash
source <(.circleci/set_env.sh prod)

# Output:
export AWS_ACCOUNT_ID=872406820375
export VPC_NAME=prod
export VPC_PREFIX=prod
export EKS_CLUSTER_ARN=arn:aws:eks:us-west-2:872406820375:cluster/eks-prod
export DOCKER_TAG=v1.2.3  # Extracted from release tag
```

#### 2. Base Image Excludes Dev/Test Gems
```bash
# Dockerfile.base lines are NOT removed:
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
```

#### 3. Infrastructure Paths
```bash
SERVICE_PATH="prod/us-west-2/prod/apps/rails-api"
CLOCKWORK_PATH="prod/us-west-2/prod/apps/clockwork"
SIDEKIQ_PATH="prod/us-west-2/prod/apps/sidekiq"
```

#### 4. Environment File
Container uses `/config/prod.env` which contains:
- Encrypted production credentials
- Production URLs
- Production feature flags
- `RAILS_ENV=production`

---

## Feature Environment Deployment

### Trigger
- Push to `feature/*` branch (e.g., `feature/new-loan-flow`)

### Special Behavior

#### 1. Extract Feature Name
```bash
export FEATURE_NAME=$(echo feature/new-loan-flow | sed -e 's^feature/^^')
# FEATURE_NAME=new-loan-flow

export DOCKER_TAG=feat-new-loan-flow-a1b2c3d
```

#### 2. Generate Infrastructure
```bash
# Clone infrastructure-live repo
cd /tmp/infrastructure-live/dev/us-west-2/dev/services/k8s-feature

# Generate isolated services for this feature
POSTGRES_PATH=dev/us-west-2/dev/apps/features/$(./generate-dependency.sh $FEATURE_NAME postgres)
REDIS_PATH=dev/us-west-2/dev/apps/features/$(./generate-dependency.sh $FEATURE_NAME redis)
PGADMIN_PATH=dev/us-west-2/dev/apps/features/$(./generate.sh $FEATURE_NAME pgadmin rubysolo/pgadmin4-auto latest 80)
SERVICE_PATH=dev/us-west-2/dev/apps/features/$(./generate.sh $FEATURE_NAME api $DOCKER_IMAGE $DOCKER_TAG 8080)
CLOCKWORK_PATH=dev/us-west-2/dev/apps/features/$(./generate.sh $FEATURE_NAME clockwork $DOCKER_IMAGE $DOCKER_TAG 8080 'SERVER_FLAVOR = "scheduler"')
SIDEKIQ_PATH=dev/us-west-2/dev/apps/features/$(./generate.sh $FEATURE_NAME sidekiq $DOCKER_IMAGE $DOCKER_TAG 8080 'SERVER_FLAVOR = "worker"')

# Commit to infrastructure-live
git-add-commit-push \
  --path "/tmp/infrastructure-live/${POSTGRES_PATH}/terragrunt.hcl" \
  --path "/tmp/infrastructure-live/${REDIS_PATH}/terragrunt.hcl" \
  --path "/tmp/infrastructure-live/${PGADMIN_PATH}/terragrunt.hcl" \
  --path "/tmp/infrastructure-live/${SERVICE_PATH}/terragrunt.hcl" \
  --path "/tmp/infrastructure-live/${CLOCKWORK_PATH}/terragrunt.hcl" \
  --path "/tmp/infrastructure-live/${SIDEKIQ_PATH}/terragrunt.hcl" \
  --message "Deploy feature env '${FEATURE_NAME}' with tag '${DOCKER_TAG}'" \
  --skip-ci-flag "[ci skip]"
```

#### 3. Deploy Dependencies
```bash
# Deploy PostgreSQL
terragrunt apply \
  --terragrunt-working-dir "/tmp/infrastructure-live/$POSTGRES_PATH" \
  -input=false \
  -auto-approve

# Deploy Redis
terragrunt apply \
  --terragrunt-working-dir "/tmp/infrastructure-live/$REDIS_PATH" \
  -input=false \
  -auto-approve

# Deploy PgAdmin
terragrunt apply \
  --terragrunt-working-dir "/tmp/infrastructure-live/$PGADMIN_PATH" \
  -input=false \
  -auto-approve
```

#### 4. Deploy Application Services
```bash
# Deploy Clockwork, Sidekiq, API (same as dev)
terragrunt apply --terragrunt-working-dir "/tmp/infrastructure-live/$CLOCKWORK_PATH" -input=false -auto-approve
terragrunt apply --terragrunt-working-dir "/tmp/infrastructure-live/$SIDEKIQ_PATH" -input=false -auto-approve
terragrunt apply --terragrunt-working-dir "/tmp/infrastructure-live/$SERVICE_PATH" -input=false -auto-approve
```

### Feature Cleanup
When feature branch is deleted:

```bash
# Workflow: teardown-feature
# Triggered by GitHub webhook: GHA_Event = "delete"

.circleci/feature-cleanup.sh $FEATURE_NAME

# Destroys all Terragrunt resources for that feature
```

---

## Docker Image Build Process

### Two-Stage Build

#### Stage 1: Base Image (Cached)
**File:** `Dockerfile.base`

```bash
# Triggered only when dependencies change
# Checksum: cat Gemfile Gemfile.lock Dockerfile.base | sha1sum

# 1. Install system packages
FROM ruby:3.1.4
RUN apt-get install -y build-essential nodejs pdftk wkhtmltopdf

# 2. Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
RUN cd /tmp && unzip awscliv2.zip && /tmp/aws/install

# 3. Install gruntkms
ENV GRUNTWORK_INSTALLER_VERSION v0.0.38
ENV GRUNTKMS_VERSION v0.0.11
RUN curl -Ls https://raw.githubusercontent.com/gruntwork-io/gruntwork-installer/master/bootstrap-gruntwork-installer.sh | \
    bash /dev/stdin --version "$GRUNTWORK_INSTALLER_VERSION"
RUN gruntwork-install --repo "https://github.com/blinkergit/gruntkms" \
                      --binary-name "gruntkms" \
                      --tag "$GRUNTKMS_VERSION"

# 4. Install Ruby gems
WORKDIR /var/www/blinker
COPY Gemfile Gemfile.lock vendor ./
RUN bundle config github.com $GITHUB_OAUTH_TOKEN:x-oauth-basic
RUN bundle install --jobs 3 --retry 3

# For production: exclude dev/test gems
# RUN bundle config set --local without 'development test'
```

**Tag:** `004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:base-<checksum>`

#### Stage 2: Application Image
**File:** `Dockerfile`

```bash
# Uses base image as starting point
ARG BASE_IMAGE_NAME
FROM ${BASE_IMAGE_NAME}

# 1. Copy application code
COPY . .

# 2. Copy encrypted environment files
RUN mkdir /config
COPY config/*.env /config/

# 3. Configure database and unicorn
RUN cd /var/www/blinker/config && \
    rm -f database.yml && \
    mv database.docker.yml database.yml
RUN cd /var/www/blinker/config && \
    rm -f unicorn.rb && \
    ln -s unicorn.rb.sample unicorn.rb

# 4. Expose ports
EXPOSE 8080 25658

# 5. Set entrypoint
CMD [ "bin/env" ]
```

**Tag:** 
- Dev: `004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:<CIRCLE_SHA1>`
- Feature: `004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:feat-<feature-name>-<short-sha>`
- Prod: `004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:v1.2.3`

---

## Database Migrations

### Automatic Migration (Kubernetes)

When a server pod starts:

```ruby
# script/entrypoint.rb

class DockerEntrypoint
  def setup_database
    # Check if database exists
    unless @postgres.database_exists?
      execute_with_elevated_access("bundle exec rake db:create")
    end
    
    # Run migrations with superuser credentials
    execute_with_elevated_access("bundle exec rake db:migrate db:grant")
    
    # Seed database
    execute_with_elevated_access("bundle exec rake db:seed:#{environment}")
  end
end
```

**Key Points:**
- Each pod checks if database exists
- Uses `DATABASE_SUPER_USERNAME` and `DATABASE_SUPER_PASSWORD` for migrations
- Safe with rolling deployments (multiple pods can attempt concurrently)
- Database grants are applied for normal user after migration

### Manual Migration (if needed)

```bash
# SSH into Kubernetes pod
kubectl exec -it rails-api-<pod-id> -- bash

# Run migration manually
RAILS_ENV=production bundle exec rake db:migrate

# Or using the entrypoint script
bundle exec ruby script/entrypoint.rb migrate
```

---

## Environment Variables Management

### Storage: `config/*.env`

Three environment files:
- `config/dev.env` - Development environment
- `config/stage.env` - Staging environment  
- `config/prod.env` - Production environment

### Encryption with KMS

Sensitive values are encrypted with AWS KMS using `kmscrypt` format:

```bash
# Plain text
GRAVITY_API_PASSWORD=MySecretPassword123

# Encrypted (in config/prod.env)
GRAVITY_API_PASSWORD=kmscrypt::AQICAHh6wQ9vWFxY6EHEYM1zvyd6PFx6f3NIMs/DuFjUuQ10aQEstbMxlZjPf3ryDYVhmwjCAAAAojCBnwYJKoZIhvcNAQcGoIGRMIGOAgEAMIGIBgkqhkiG9w0BBwEwHgYJYIZIAWUDBAEuMBEEDH1UFrb674OMBZaCVAIBEIBbdisblAZBHGVQZ9mwiFqTc+EXsQ+h1Z49CEdStkCupydlQSFDH95QQkuTWjXrzy1/b9sNOhTSIqXmWYO5ENRNYHvkRNPgXgpCsjDN2egcLI0dEN1BPfyJRYh5IQ==
```

### Decryption at Runtime

```bash
# Script: bin/env

# 1. Read encrypted file
encrypted_config=$(cat "/config/$VPC_NAME.env")

# 2. Decrypt using gruntkms (requires AWS IAM permissions)
decrypted_config=$(gruntkms decrypt --aws-region "$AWS_REGION" --ciphertext "$encrypted_config")

# 3. Load into environment via named pipe (secure, in-memory only)
mkfifo /tmp/.envrc
(echo -e "$decrypted_config" > /tmp/.envrc && rm -f /tmp/.envrc) &

while read -r key val; do
  # Check if already set (allows Kubernetes overrides)
  if [[ -z "${!key+x}" ]]; then
    export $key="$val"
  fi
done < /tmp/.envrc

# 4. Start application with decrypted environment
bundle exec ruby script/entrypoint.rb $FLAVOR
```

### Adding New Environment Variables

#### For Development:
```bash
# Edit config/dev.env
echo "NEW_API_KEY=test-key" >> config/dev.env

# Commit and push
git add config/dev.env
git commit -m "Add NEW_API_KEY to dev environment"
git push origin da/develop

# Restart pods to pick up new env var
kubectl rollout restart deployment/rails-api -n dev
```

#### For Production:
```bash
# Encrypt the value
gruntkms encrypt --aws-region us-west-2 --plaintext "production-secret-key"
# Output: kmscrypt::AQICAHh6wQ9vWFxY...

# Edit config/prod.env
echo "NEW_API_KEY=kmscrypt::AQICAHh6wQ9vWFxY..." >> config/prod.env

# Commit and deploy via release tag
git add config/prod.env
git commit -m "Add encrypted NEW_API_KEY to prod environment"
git tag release-v1.2.4
git push origin release-v1.2.4
```

---

## Detailed Script Analysis

### `.circleci/config.yml`

**Workflow:** `test-build-deploy`

```yaml
jobs:
  - validate-branch-name  # Ensure feature names are valid
  - rubocop              # Lint code
  - refresh-base-image   # Build/cache base Docker image (parallel)
  - run-tests            # Run RSpec tests (parallel, 8 workers)
  - deploy               # Build app image, update infra, deploy to k8s
    requires:
      - run-tests
      - refresh-base-image
```

### `.circleci/deploy.sh`

**Purpose:** Orchestrates Docker build and Kubernetes deployment

```bash
# 1. Determine environment from branch/tag
if [[ "$CIRCLE_TAG" =~ ^release-.*$ ]]; then
  VPC_NAME=prod
  DOCKER_TAG=$(echo $CIRCLE_TAG | sed -e 's/release-//')
elif [[ "$CIRCLE_BRANCH" == "da/develop" ]]; then
  VPC_NAME=dev
  DOCKER_TAG=$CIRCLE_SHA1
elif [[ "$CIRCLE_BRANCH" == feature/* ]]; then
  VPC_NAME=dev
  DOCKER_TAG=feat-${FEATURE_NAME}-${CIRCLE_SHA1:0:7}
fi

# 2. Set environment variables
source <(.circleci/set_env.sh $VPC_NAME $CIRCLE_BRANCH)

# 3. Build and push Docker image
build-docker-image \
  --docker-image-name "$DOCKER_IMAGE" \
  --docker-image-tag "$DOCKER_TAG" \
  --build-arg BASE_IMAGE_NAME="$BASE_IMAGE_NAME"

# 4. Update infrastructure-live repo
terraform-update-variable --name "image_version" --value "\"$DOCKER_TAG\"" ...

# 5. Assume AWS role and configure kubectl
source <(assume_role.sh $AWS_ACCOUNT_ID)
kubergrunt eks configure --eks-cluster-arn $EKS_CLUSTER_ARN

# 6. Apply Terragrunt (deploy to Kubernetes)
terragrunt apply --terragrunt-working-dir "$SERVICE_PATH" -auto-approve
```

### `build_base.sh`

**Purpose:** Build and push base Docker image (only when dependencies change)

```bash
# Calculate checksum
DEPENDENCY_CHECKSUM=$(cat Gemfile Gemfile.lock Dockerfile.base | sha1sum)

# Check if image already exists in ECR
docker pull $BASE_IMAGE_NAME || {
  # Build new image
  docker build -t $BASE_IMAGE_NAME \
               --build-arg GITHUB_OAUTH_TOKEN=$GITHUB_OAUTH_TOKEN \
               -f Dockerfile.base .
  
  # Push to ECR
  docker push $BASE_IMAGE_NAME
}
```

### `bin/env`

**Purpose:** Decrypt environment variables and start application

```bash
# 1. Decrypt config file
encrypted_config=$(cat "/config/$VPC_NAME.env")
decrypted_config=$(gruntkms decrypt --aws-region "$AWS_REGION" --ciphertext "$encrypted_config")

# 2. Load into environment (secure, memory-only)
mkfifo /tmp/.envrc
(echo -e "$decrypted_config" > /tmp/.envrc && rm -f /tmp/.envrc) &

while read -r key val; do
  [[ -z "${!key+x}" ]] && export $key="$val"
done < /tmp/.envrc

# 3. Start application
bundle exec ruby script/entrypoint.rb $FLAVOR
```

### `script/entrypoint.rb`

**Purpose:** Start appropriate service based on `SERVER_FLAVOR`

```ruby
class DockerEntrypoint
  def call
    setup_database if flavor == "server"
    actualize
  end
  
  def actualize
    exec command
  end
  
  def command
    case flavor
    when "server"    then "bundle exec unicorn"
    when "worker"    then "bundle exec sidekiq -v -C ./config/sidekiq.yml"
    when "scheduler" then "bundle exec clockwork ./config/schedule.rb"
    when "migrate"   then "bundle exec rails db:migrate"
    when "console"   then "bundle exec rails console"
    end
  end
  
  def setup_database
    unless @postgres.database_exists?
      execute_with_elevated_access("bundle exec rake db:create")
    end
    execute_with_elevated_access("bundle exec rake db:migrate db:grant")
    execute_with_elevated_access("bundle exec rake db:seed:#{seed_environment}")
  end
end

# Start entrypoint
DockerEntrypoint.factory(ARGV.first).call
```

---

## Summary of Commands

### Local Development
```bash
# Build base image
./build_base.sh

# Build app image
docker build -t blinker-api:local --build-arg BASE_IMAGE_NAME=blinker-api:base .

# Run locally
docker run -e VPC_NAME=dev -e AWS_REGION=us-west-2 blinker-api:local
```

### CircleCI (Automatic)
```bash
# Triggered on push to da/develop
# 1. Validate branch
# 2. Run rubocop
# 3. Build/cache base image
# 4. Run tests (8 parallel workers)
# 5. Build app image
# 6. Update Terragrunt configs
# 7. Deploy to Kubernetes
```

### Kubernetes (Container Startup)
```bash
# 1. Decrypt environment
gruntkms decrypt --aws-region us-west-2 --ciphertext "$(cat /config/dev.env)"

# 2. Check database connectivity
# 3. Run migrations (if server pod)
bundle exec rake db:migrate

# 4. Start service
bundle exec unicorn              # Server
bundle exec sidekiq              # Worker
bundle exec clockwork schedule.rb # Scheduler
```

### Manual Deployment
```bash
# Deploy to production
git tag release-v1.2.3
git push origin release-v1.2.3

# Deploy to dev
git push origin da/develop

# Deploy feature environment
git push origin feature/my-new-feature

# Cleanup feature environment
# Delete branch on GitHub (webhook triggers teardown)
```

---

## Troubleshooting

### Check CircleCI Build Status
```bash
# View in CircleCI dashboard
https://app.circleci.com/pipelines/github/BlinkerGit/blinker
```

### Check Kubernetes Pods
```bash
# Configure kubectl
aws eks update-kubeconfig --name eks-dev --region us-west-2

# List pods
kubectl get pods -n dev

# View logs
kubectl logs rails-api-<pod-id> -n dev

# Shell into pod
kubectl exec -it rails-api-<pod-id> -n dev -- bash

# Check environment variables
kubectl exec rails-api-<pod-id> -n dev -- env | grep GRAVITY
```

### Check Docker Images
```bash
# List images in ECR
aws ecr list-images --repository-name rails-api --region us-west-2

# Pull and inspect
docker pull 004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:<tag>
docker inspect 004671295794.dkr.ecr.us-west-2.amazonaws.com/rails-api:<tag>
```

### Decrypt Environment File Locally
```bash
# Requires AWS credentials with KMS decrypt permissions
gruntkms decrypt --aws-region us-west-2 --ciphertext "$(cat config/dev.env)"
```

---

**Last Updated:** November 10, 2025  
**Maintained By:** DevOps Team

