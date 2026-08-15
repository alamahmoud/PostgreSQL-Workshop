FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev && npm cache clean --force
COPY server.js ./
COPY public ./public
ENV NODE_ENV=production
EXPOSE 8080
CMD ["node", "server.js"]
