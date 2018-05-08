FROM ruby:2.3.1

# Install essentials
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev postgresql-client libgeos-dev systemd-sysv

# Setup /data/banco_de_dados
WORKDIR /data/banco_de_dados

# Install bundler
RUN gem install bundler -v 1.16.1

# Install gems
COPY components /data/banco_de_dados/components
COPY Gemfile /data/banco_de_dados/Gemfile
COPY Gemfile.lock /data/banco_de_dados/Gemfile.lock
RUN bundle install

# Install application
COPY . /data/banco_de_dados
