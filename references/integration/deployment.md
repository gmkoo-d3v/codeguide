# Deployment Strategies

Extracted verbatim from references/integration-patterns.md for Phase 4 index-ization.

## Deployment Strategies

### Monolith (Embedded Frontend)

**Spring Boot with React build:**
```xml
<!-- pom.xml -->
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <executions>
        <execution>
            <id>npm install</id>
            <goals><goal>npm</goal></goals>
            <configuration>
                <arguments>install</arguments>
            </configuration>
        </execution>
        <execution>
            <id>npm build</id>
            <goals><goal>npm</goal></goals>
            <configuration>
                <arguments>run build</arguments>
            </configuration>
        </execution>
    </executions>
</plugin>

<plugin>
    <artifactId>maven-resources-plugin</artifactId>
    <executions>
        <execution>
            <id>copy-frontend</id>
            <phase>process-resources</phase>
            <goals><goal>copy-resources</goal></goals>
            <configuration>
                <outputDirectory>${project.build.outputDirectory}/static</outputDirectory>
                <resources>
                    <resource>
                        <directory>frontend/build</directory>
                    </resource>
                </resources>
            </configuration>
        </execution>
    </executions>
</plugin>
```

**Application Properties:**
```yaml
# application.yml
spring:
  web:
    resources:
      static-locations: classpath:/static/
  mvc:
    view:
      prefix: /
      suffix: .html
```

**Serve Frontend:**
```java
@Controller
public class FrontendController {
    @GetMapping(value = "/{path:[^\\.]*}")
    public String forward() {
        return "forward:/index.html";
    }
}
```

### Separate Deployments

**Backend (Docker):**
```dockerfile
# Dockerfile
FROM openjdk:17-jdk-slim
WORKDIR /app
COPY target/app.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

**Frontend (Nginx):**
```dockerfile
# Dockerfile
FROM node:18 AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

**Nginx Config:**
```nginx
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Docker Compose:**
```yaml
version: '3.8'
services:
  backend:
    build: ./backend
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=prod

  frontend:
    build: ./frontend
    ports:
      - "80:80"
    depends_on:
      - backend
```

### CI/CD Pipeline

**GitHub Actions:**
```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-java@v3
        with:
          java-version: '17'
      - run: mvn test

  test-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm ci
      - run: npm test

  deploy:
    needs: [test-backend, test-frontend]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push Docker images
        run: |
          docker build -t myapp-backend ./backend
          docker build -t myapp-frontend ./frontend
          docker push myapp-backend
          docker push myapp-frontend
      - name: Deploy to production
        run: |
          # SSH to server and pull/restart containers
```

---

