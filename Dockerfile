# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.1.2
FROM ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"


# Throw-away build stage to reduce size of final image
FROM base as build

# Install packages needed to build gems and compile assets (including Node.js for Tailwind)
# Split into separate RUN to improve caching - apt-get update is cached separately
RUN apt-get update -qq
RUN apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libpq-dev \
    libvips \
    pkg-config \
    nodejs \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Create directories needed for asset compilation (Tailwind output, etc.)
RUN mkdir -p app/assets/builds/solidus_admin tmp/cache public/assets

# Precompile assets (including Tailwind CSS) to avoid SassC errors at runtime
# Use RAILS_GROUPS=assets to only load asset-related code and skip database
# RAILS_MASTER_KEY is passed from CircleCI environment variables during build
# CSS compression is disabled in production.rb to prevent SassC errors
ARG RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 \
    RAILS_MASTER_KEY=${RAILS_MASTER_KEY} \
    RAILS_GROUPS=assets \
    RAILS_ENV=production \
    ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment (including Node.js for runtime asset compilation)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libvips postgresql-client nodejs && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Healthcheck for Docker and Kamal
HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3001/up || exit 1

# Start the server by default, this can be overwritten at runtime
EXPOSE 3001
CMD ["./bin/rails", "server"]
