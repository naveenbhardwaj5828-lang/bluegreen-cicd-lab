#!/bin/sh
set -e

APP_VERSION="${APP_VERSION:-unknown}"
APP_ENVIRONMENT="${APP_ENVIRONMENT:-unknown}"

# Controlled rollback test:
# CI behaves normally, but BLUE/GREEN intentionally shows a bad version.
if [ "$APP_ENVIRONMENT" = "CI" ]; then
    DISPLAY_VERSION="$APP_VERSION"
else
    DISPLAY_VERSION="BROKEN-RELEASE"
fi

sed \
  -e "s/__APP_VERSION__/${DISPLAY_VERSION}/g" \
  -e "s/__APP_ENVIRONMENT__/${APP_ENVIRONMENT}/g" \
  /usr/share/nginx/html/index.template.html \
  > /usr/share/nginx/html/index.html

exec nginx -g 'daemon off;'