# 1. Use minimal base image (smaller attack surface)
FROM node:18-alpine

# 2. Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# 3. Set working directory
WORKDIR /app

# 4. Copy only package files first (better caching, less exposure)
COPY package*.json ./

# 5. Install only production dependencies
RUN npm ci --only=production && npm cache clean --force

# 6. Copy rest of the app
COPY . .

# 7. Set correct file permissions
RUN chown -R appuser:appgroup /app

# 8. Switch to non-root user
USER appuser

# 9. Expose only required port
EXPOSE 8080

# 10. Run app
CMD ["node", "server.js"]