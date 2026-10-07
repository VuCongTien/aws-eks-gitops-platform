FROM node:20-alpine

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm install --omit=dev

COPY src ./src

EXPOSE 5000

ENV PORT=5000 \
    NODE_ENV=production

CMD ["node", "src/server.js"]
