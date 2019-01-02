FROM ruby:2.5

ENV APP_ROOT /usr/src/devise-api

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs
# SQLite
RUN apt-get install sqlite3 libsqlite3-dev -y

RUN mkdir $APP_ROOT
WORKDIR $APP_ROOT
COPY Gemfile $APP_ROOT/Gemfile
RUN bundle install
COPY . $APP_ROOT
