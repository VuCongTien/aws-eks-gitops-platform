# AWS EKS Lab - Backend Service

Node.js Express backend service designed for AWS EKS Production-like GitOps Lab testing.

## Features & AWS Integration
1. **Pod Topology & Multi-AZ**: Reads K8s Downward API (`POD_NAME`, `NODE_NAME`, `NODE_AZ`) to report which Pod and AZ handled the request.
2. **AWS Secrets Manager**: Fetches PostgreSQL credentials dynamically via AWS SDK using **IAM Roles for Service Accounts (IRSA)** without hardcoded access keys.
3. **AWS AppConfig**: Retrieves dynamic runtime configuration profiles.
4. **RDS PostgreSQL**: Stores page visit logs and tests DB subnet connectivity.
5. **Autoscaling Test**: `/api/stress` endpoint drives CPU utilization to trigger K8s **Horizontal Pod Autoscaler (HPA)**.

## Environment Variables
- `PORT`: Port to listen on (default `5000`)
- `POD_NAME`: Name of the Kubernetes Pod (`metadata.name`)
- `NODE_NAME`: Name of the Kubernetes Node (`spec.nodeName`)
- `NODE_AZ`: Availability Zone of the Node (e.g. `ap-southeast-1a`)
- `POD_NAMESPACE`: K8s Namespace (`metadata.namespace`)
- `AWS_REGION`: AWS Region (default `ap-southeast-1`)
- `SECRET_NAME`: AWS Secrets Manager secret identifier (`prod/rds/postgres`)
- `APPCONFIG_APPLICATION`, `APPCONFIG_ENVIRONMENT`, `APPCONFIG_PROFILE`: AWS AppConfig configuration parameters

## API Endpoints
- `GET /health` - Healthcheck endpoint (200 OK)
- `GET /api/info` - Detailed topology, Secrets Manager & AppConfig status
- `GET /api/db/visits` - Fetch page visit log history from RDS PostgreSQL
- `POST /api/db/visit` - Record new page visit into RDS PostgreSQL
- `ALL /api/stress?seconds=15` - Execute heavy CPU calculations to trigger HPA scaling
