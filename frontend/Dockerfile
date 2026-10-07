FROM node:20-alpine

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm install --omit=dev

COPY src ./src
COPY public ./public

EXPOSE 3000

ENV PORT=3000 \
    NODE_ENV=production \
    BACKEND_URL=http://backend-service:5000

CMD ["node", "src/server.js"]
