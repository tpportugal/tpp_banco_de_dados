#!/bin/bash
docker-compose -f docker-compose.development.yml stop
docker-compose -f docker-compose.staging.yml stop
docker-compose -f docker-compose.production.yml stop
