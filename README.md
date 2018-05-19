# TPP Datastore

[![Official Port](https://img.shields.io/badge/Port-8004-blue.svg)](https://github.com/tpportugal/tpp/blob/master/PORTS.md)

A community-run and -edited timetable and map of public transit services in Portugal.

***For more information about TPP as a whole, and how to use the Datastore in particular, view the [TPP documentation site](https://tpp.pt/documentation).***

This readme describes the TPP Datastore behind the scenes: a Ruby on Rails web service (backed by Postgres/PostGIS), along with an asynchronous Sidekiq queue (backed by Resque) that runs Ruby and Python data-ingestion libraries.

Note that this web application is designed to run at `https://tpp.pt/api/v1` While you're welcome to try hosting your own instance, please keep in mind that the TPP Datastore is intended to be a centralized source of data run by a community in one place (much like [the Rails app that powers the openstreetmap.org API](https://github.com/openstreetmap/openstreetmap-website)).

## Deploying with Docker
First of all set your correspondent environment. At the folder `./env` you will find 3 examples:
 - `example.development`
 - `example.staging`
 - `example.production`  

Remove the prefix `example.` from your desired environment and the env file will be active.

Now, just run the script `run.sh` with your desired environment and the datastore will be up & running.

Run-Example for development:

  `./run.sh -e development`

If you want to run the datastore in background-mode, just add the option `-d`:

 `./run.sh -d -e development`

For stopping all datastore services, please run:
 `./stop.sh`


## Technical documentation

- [Local instructions](doc/local-instructions.md)
- [API endpoints](https://tpp.pt/documentation/datastore/api-endpoints.html)
- [Configuration reference](doc/configuration.md)
- [Development practices](doc/development-practices.md)
- [Conflation with OSM](doc/conflation-with-osm.md)
- [Admin interface](doc/admin-interface.md)
- [Authentication](doc/authentication.md)

## See also

- [changelog](CHANGELOG.md)
- [contributing](CONTRIBUTING.md)
- [license](LICENSE.txt)
