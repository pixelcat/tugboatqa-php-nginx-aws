#!/usr/bin/env bash

if [[ ! -d tugboat-tools ]]; then
  git clone git@bitbucket.org:speareducation/tugboat-tools
else
  pushd tugboat-tools 2>&1 > /dev/null
  git pull
  popd 2>&1 > /dev/null
fi

docker pull tugboatqa/php:7.2.16-fpm-stretch
docker build -t spear/tugboatqa-php-nginx:1.0-7.2.16-fpm-stretch-1 .
