# Templates Reutilizáveis - CI/CD OficinaPro

Este arquivo contém snippets reutilizáveis para pipelines CI/CD padronizadas.

## 1. Busca Dinâmica de Recursos AWS

### 1.1 Buscar K3s Master IP

```yaml
- name: 'Buscar K3s Master IP'
  id: k3s-discovery
  run: |
    echo "📍 Buscando K3s Master IP..."
    
    # Prioridade 1: Por tag Role=master
    MASTER_IP=$(aws ec2 describe-instances \
      --filters "Name=tag:Role,Values=master" "Name=instance-state-name,Values=running" \
      --query "Reservations[0].Instances[0].PublicIpAddress" \
      --output text 2>/dev/null)
    
    # Prioridade 2: Por instance type (m7i-flex.large) + running
    if [ "$MASTER_IP" == "None" ] || [ -z "$MASTER_IP" ]; then
      MASTER_IP=$(aws ec2 describe-instances \
        --filters "Name=instance-type,Values=m7i-flex.large" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text 2>/dev/null)
    fi
    
    # Prioridade 3: Buscar em Parameter Store (cache)
    if [ "$MASTER_IP" == "None" ] || [ -z "$MASTER_IP" ]; then
      MASTER_IP=$(aws ssm get-parameter \
        --name "/oficinapro/k3s/master-ip" \
        --query "Parameter.Value" \
        --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$MASTER_IP" ] || [ "$MASTER_IP" == "None" ]; then
      echo "::error::K3s Master não encontrado"
      exit 1
    fi
    
    echo "master_ip=${MASTER_IP}" >> $GITHUB_OUTPUT
    echo "✅ K3s Master: ${MASTER_IP}"
```

### 1.2 Buscar RDS Endpoint

```yaml
- name: 'Buscar RDS Endpoint'
  id: rds-discovery
  run: |
    echo "📍 Buscando RDS Endpoint..."
    
    # Prioridade 1: Instância consolidada atual
    RDS_HOST=$(aws rds describe-db-instances \
      --db-instance-identifier oficinapro-consolidated-db \
      --query 'DBInstances[0].Endpoint.Address' \
      --output text 2>/dev/null || echo "")
    
    # Prioridade 2: Pattern matching (fase4/consolidated/oficinapro)
    if [ -z "$RDS_HOST" ] || [ "$RDS_HOST" == "None" ]; then
      RDS_HOST=$(aws rds describe-db-instances \
        --query 'DBInstances[?contains(DBInstanceIdentifier, `fase4`) || contains(DBInstanceIdentifier, `consolidated`)].Endpoint.Address | [0]' \
        --output text 2>/dev/null || echo "")
    fi
    
    # Prioridade 3: Primeira instância available
    if [ -z "$RDS_HOST" ] || [ "$RDS_HOST" == "None" ]; then
      RDS_HOST=$(aws rds describe-db-instances \
        --query 'DBInstances[?DBInstanceStatus==`available`].Endpoint.Address | [0]' \
        --output text 2>/dev/null || echo "")
    fi
    
    # Fallback: Endpoint conhecido (verificado 2026-01-26)
    if [ -z "$RDS_HOST" ] || [ "$RDS_HOST" == "None" ]; then
      RDS_HOST="oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1.rds.amazonaws.com"
      echo "⚠️  Usando RDS endpoint fallback"
    fi
    
    echo "rds_host=${RDS_HOST}" >> $GITHUB_OUTPUT
    echo "✅ RDS Endpoint: ${RDS_HOST}"
```

### 1.3 Buscar SQS Queue URLs (Billing)

```yaml
- name: 'Buscar SQS Queue URLs'
  id: sqs-discovery
  run: |
    echo "📍 Buscando SQS Queue URLs..."
    
    # Pattern: oficinapro-{service}-{type}.fifo
    # Exemplo para Billing Service
    SQS_EVENTS=$(aws sqs get-queue-url \
      --queue-name oficinapro-billing-events.fifo \
      --query 'QueueUrl' \
      --output text 2>/dev/null || echo "")
    echo "sqs_events=${SQS_EVENTS}" >> $GITHUB_OUTPUT
    
    SQS_COMMANDS=$(aws sqs get-queue-url \
      --queue-name oficinapro-billing-commands.fifo \
      --query 'QueueUrl' \
      --output text 2>/dev/null || echo "")
    echo "sqs_commands=${SQS_COMMANDS}" >> $GITHUB_OUTPUT
    
    SQS_DLQ=$(aws sqs get-queue-url \
      --queue-name oficinapro-saga-dlq.fifo \
      --query 'QueueUrl' \
      --output text 2>/dev/null || echo "")
    echo "sqs_dlq=${SQS_DLQ}" >> $GITHUB_OUTPUT
    
    echo "✅ SQS Queues configuradas"
```

## 2. Dockerfile com OpenTelemetry (Java)

```dockerfile
# Multi-stage build with OpenTelemetry

# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn clean package -Dmaven.test.skip=true -B

# Stage 2: Download OpenTelemetry Java Agent
FROM curlimages/curl:latest AS otel-downloader
WORKDIR /otel
RUN curl -L -o opentelemetry-javaagent.jar \
    https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

# Stage 3: Runtime
FROM eclipse-temurin:21-jre
WORKDIR /app

RUN groupadd -r spring && useradd -r -g spring spring

COPY --from=build /app/target/*.jar app.jar
COPY --from=otel-downloader /otel/opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar

RUN chown -R spring:spring /app
USER spring:spring

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8082/actuator/health || exit 1

EXPOSE 8082

ENV JAVA_OPTS="-XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -XX:+UseG1GC \
    -javaagent:/app/opentelemetry-javaagent.jar \
    -Dotel.service.name=${OTEL_SERVICE_NAME:-service-name} \
    -Dotel.exporter.otlp.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT:-https://otlp.nr-data.net:4318} \
    -Dotel.exporter.otlp.headers=api-key=${NEW_RELIC_LICENSE_KEY} \
    -Dotel.traces.exporter=otlp \
    -Dotel.metrics.exporter=otlp \
    -Dotel.logs.exporter=none"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

## 3. Kubernetes Manifests (Java Service)

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: {SERVICE_NAME}-config
  namespace: oficinapro-prod
data:
  DB_HOST: "${RDS_HOST}"
  DB_PORT: "5432"
  DB_NAME: "{db_name}"
  DB_USER: "oficinapro_admin"
  AWS_REGION: "us-east-1"
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  OTEL_SERVICE_NAME: "{service-name}"
  OTEL_EXPORTER_OTLP_ENDPOINT: "https://otlp.nr-data.net:4318"
  SPRING_PROFILES_ACTIVE: "prod"

---
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {SERVICE_NAME}
  namespace: oficinapro-prod
  labels:
    app: {SERVICE_NAME}
    version: v1
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: {SERVICE_NAME}
  template:
    metadata:
      labels:
        app: {SERVICE_NAME}
        version: v1
    spec:
      imagePullSecrets:
      - name: ghcr-secret
      containers:
      - name: {SERVICE_NAME}
        image: ghcr.io/${OWNER}/{SERVICE_NAME}:${SHA}
        imagePullPolicy: Always
        ports:
        - containerPort: {PORT}
          name: http
        envFrom:
        - configMapRef:
            name: {SERVICE_NAME}-config
        - secretRef:
            name: {SERVICE_NAME}-secrets
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: {PORT}
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: {PORT}
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /actuator/health
            port: {PORT}
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 30

---
# Service
apiVersion: v1
kind: Service
metadata:
  name: {SERVICE_NAME}
  namespace: oficinapro-prod
  labels:
    app: {SERVICE_NAME}
spec:
  type: ClusterIP
  ports:
  - port: {PORT}
    targetPort: {PORT}
    protocol: TCP
    name: http
  selector:
    app: {SERVICE_NAME}

---
# HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {SERVICE_NAME}-hpa
  namespace: oficinapro-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {SERVICE_NAME}
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## 4. Liquibase Schema Creation Fix

```sql
-- liquibase formatted sql

-- changeset system:00-create-schema-{service}
-- Cria o schema se não existir
CREATE SCHEMA IF NOT EXISTS {schema_name};

-- Configurar search_path para o schema correto (CRÍTICO)
SET search_path TO {schema_name}, public;

-- Grant permissions (multi-user support)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'oficinapro_admin') THEN
        GRANT ALL PRIVILEGES ON SCHEMA {schema_name} TO oficinapro_admin;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA {schema_name} TO oficinapro_admin;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA {schema_name} TO oficinapro_admin;
        ALTER DEFAULT PRIVILEGES IN SCHEMA {schema_name} GRANT ALL PRIVILEGES ON TABLES TO oficinapro_admin;
        ALTER DEFAULT PRIVILEGES IN SCHEMA {schema_name} GRANT ALL PRIVILEGES ON SEQUENCES TO oficinapro_admin;
    END IF;
END $$;

-- rollback DROP SCHEMA IF EXISTS {schema_name} CASCADE;
```

## 5. Application Properties (Liquibase + Observabilidade)

```properties
# Liquibase (configuração completa)
spring.liquibase.enabled=true
spring.liquibase.change-log=classpath:db/changelog/db.changelog-master.yaml
spring.liquibase.default-schema={schema_name}
spring.liquibase.liquibase-schema={schema_name}
spring.liquibase.lock-timeout=30
spring.liquibase.database-change-log-table=databasechangelog
spring.liquibase.database-change-log-lock-table=databasechangeloglock

# Hibernate (schema padrão CRÍTICO)
spring.jpa.properties.hibernate.default_schema={schema_name}

# OpenTelemetry - Traces
otel.service.name=${OTEL_SERVICE_NAME:{service-name}}
otel.exporter.otlp.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT:https://otlp.nr-data.net:4318}
otel.exporter.otlp.headers=api-key=${NEW_RELIC_LICENSE_KEY:}
otel.traces.exporter=otlp
otel.traces.sampler=always_on

# Micrometer - Métricas para New Relic (OTLP)
management.otlp.metrics.export.enabled=${OTLP_METRICS_ENABLED:true}
management.otlp.metrics.export.url=${OTEL_EXPORTER_OTLP_ENDPOINT:https://otlp.nr-data.net:4318}/v1/metrics
management.otlp.metrics.export.step=60s
management.otlp.metrics.export.headers.api-key=${NEW_RELIC_LICENSE_KEY:}
```

---

**Como usar estes templates**:

1. Copie o snippet desejado
2. Substitua `{SERVICE_NAME}`, `{service-name}`, `{PORT}`, `{schema_name}`, `{db_name}` pelos valores corretos
3. Adapte conforme necessário (ex: SQS queue names específicos)
4. Teste localmente antes de fazer push
