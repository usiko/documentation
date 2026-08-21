FROM node:22-slim AS builder

# install git to install plugins
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
COPY package.json .
COPY package-lock.json* .
COPY .npmrc* .
COPY quartz/ ./quartz/
COPY quartz.lock.json* .
RUN npm install && npx quartz plugin install

COPY . .
RUN npx quartz build

FROM nginx:1.27-alpine

RUN apk add --no-cache openssl

COPY --from=builder /usr/src/app/public/ /usr/share/nginx/html/
COPY nginx/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY nginx/docker-entrypoint.d/05-generate-htpasswd.sh /docker-entrypoint.d/05-generate-htpasswd.sh
RUN chmod +x /docker-entrypoint.d/05-generate-htpasswd.sh

# Safe defaults: no LAN bypass (127.0.0.1/32 matches nothing real), no valid
# credential (empty .htpasswd, see 05-generate-htpasswd.sh), until a real
# .env is supplied at deploy time.
ENV ALLOWED_CIDR=127.0.0.1/32

EXPOSE 80
