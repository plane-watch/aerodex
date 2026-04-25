# syntax=docker/dockerfile:1

# Production Dockerfile for Aerodex
# Multi-stage build to keep the final image lean.

ARG RUBY_VERSION=3.3.7
FROM docker.io/library/ruby:${RUBY_VERSION}-alpine AS base

WORKDIR /rails

# Set production environment defaults
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# ---------- build stage ----------
FROM base AS build

# Install build dependencies
RUN apk add --no-cache \
      build-base \
      curl \
      git \
      libpq-dev \
      nodejs \
      npm \
      python3 \
      tzdata \
      yaml-dev && \
    npm install -g yarn@1.22.22

# Install Ruby gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Install Node.js packages
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy the rest of the application
COPY . .

# Precompile assets and bootsnap
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
RUN bundle exec bootsnap precompile app/ lib/

# ---------- runtime stage ----------
FROM base

# Install runtime dependencies only
RUN apk add --no-cache \
      curl \
      libpq \
      postgresql-client \
      tzdata \
      yaml

# Copy built artefacts from the build stage
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Create a non-root user for running the application.
# `mkdir -p` guards against missing dirs because `.dockerignore` excludes the
# contents of log/, storage/, tmp/ (including their `.keep` files), which means
# those directories may not exist in the runtime stage at this point.
RUN addgroup --system --gid 1000 rails && \
    adduser --system --uid 1000 --ingroup rails --shell /bin/sh rails && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
