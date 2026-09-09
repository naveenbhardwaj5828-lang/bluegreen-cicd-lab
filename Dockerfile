FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.template.html
COPY docker-entrypoint-app.sh /docker-entrypoint-app.sh

RUN chmod +x /docker-entrypoint-app.sh

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint-app.sh"]
