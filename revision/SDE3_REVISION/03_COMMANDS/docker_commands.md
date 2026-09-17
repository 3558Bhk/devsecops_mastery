# Docker Commands - Revision

## Basics
```bash
docker --version
docker info
docker images
docker ps
docker ps -a
docker pull nginx:latest
docker run -d --name mynginx -p 8080:80 nginx
docker run -it ubuntu bash
docker run -d -v /host:/container -e ENV=prod myapp
docker logs -f container_id
docker exec -it container_id bash
docker stop container_id
docker rm container_id
docker rmi image_id
docker system prune -a # clean all
```

## Dockerfile
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

## Build & Registry
```bash
docker build -t myapp:1.0 .
docker build --no-cache -t myapp:1.0 .
docker tag myapp:1.0 user/myapp:1.0
docker push user/myapp:1.0
docker login
docker history myapp:1.0
docker inspect myapp:1.0
```

## Docker Compose (SDE3 must)
```yaml
version: '3.8'
services:
  web:
    build: .
    ports: ["3000:3000"]
    depends_on: [db, redis]
    environment: [NODE_ENV=production]
  db:
    image: postgres:15
    volumes: [pgdata:/var/lib/postgresql/data]
    environment:
      POSTGRES_PASSWORD: secret
  redis:
    image: redis:7
volumes:
  pgdata:
```
```bash
docker-compose up -d
docker-compose down
docker-compose logs -f
docker-compose ps
docker-compose exec web bash
```

## Debugging
```bash
docker stats # resource usage
docker inspect <container>
docker logs --tail 100 <container>
docker exec <container> env
```
