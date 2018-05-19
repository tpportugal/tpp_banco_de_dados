#!/bin/bash

usage() {
	echo "Usage: $0 [-d detached] [-e <development|staging|production>]"
}

docker_run="docker-compose"
args=""

while getopts ":de:" opt; do
	case $opt in
		d)
			args="-d"
			;;
		e)
			environment=${OPTARG}
			docker_compose_file=""
			case $environment in
				development)
					docker_compose_file="-f docker-compose.development.yml"
					;;
				staging)
                    docker_compose_file="-f docker-compose.staging.yml"
					;;
				production)
                    docker_compose_file="-f docker-compose.production.yml"
					;;
				*)
					echo "Error: The environment '$environment' is not defined!" >&2
					break
					;;
			esac
			eval $docker_run "$docker_compose_file" "up" "$args"
			exit 0
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			break
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			break
			;;
		*)
			usage
			;;
	esac
done

usage
