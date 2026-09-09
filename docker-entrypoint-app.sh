#!/bin/sh
set -e

APP_VERSION="${APP_VERSION:-unknown}"
APP_ENVIRONMENT="${APP_ENVIRONMENT:-unknown}"

sed \
  -e "s/__APP_VERSION__/${APP_VERSION}/g" \
  -e "s/__APP_ENVIRONMENT__/${APP_ENVIRONMENT}/g" \
  /usr/share/nginx/html/index.template.html \
  > /usr/share/nginx/html/index.html

exec nginx -g 'daemon off;'