#!/bin/sh

source virtualenv/bin/activate

# Check specs
set -e
bundle exec rspec

# Build and push image
docker build -t tpp-datastore .
docker tag tpp-datastore:latest tpp-datastore:latest
docker push tpp-datastore:latest

