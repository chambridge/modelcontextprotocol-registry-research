FROM alpine:3.18
RUN apk add --no-cache nginx
RUN mkdir -p /var/log/nginx /var/cache/nginx /etc/nginx/conf.d
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
