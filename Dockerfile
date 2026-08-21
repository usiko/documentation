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

COPY --from=builder /usr/src/app/public/ /usr/share/nginx/html/
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# Placeholder credential file so nginx can start even before real credentials
# are provisioned (see nginx/README.md). Empty file = no valid user = every
# request outside the LAN allowlist gets a 401 until real credentials are
# mounted over this path at runtime.
RUN touch /etc/nginx/.htpasswd

EXPOSE 80
