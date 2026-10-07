# AWS EKS Lab - Frontend Web Dashboard

Interactive web dashboard built with Node.js and vanilla HTML/CSS/JS for testing the AWS EKS Production GitOps Lab.

## Features & Verification Dashboard
- **Active Pod & Multi-AZ Display**: Live badge indicating which Availability Zone (`ap-southeast-1a`, `ap-southeast-1b`, `ap-southeast-1c`) and Pod Name handled the request.
- **Traffic Load Distribution Tracker**: Keeps real-time counters and percentage bars showing ALB load balancing across pods and AZs.
- **Autoscaling (HPA) Stress Trigger**: One-click CPU load generator to test Kubernetes Horizontal Pod Autoscaling.
- **RDS PostgreSQL Inspector**: Shows database connection state and logs visits to PostgreSQL.
- **AWS IRSA & Security Inspector**: Displays IAM Role for Service Accounts (IRSA), Secrets Manager, and AWS AppConfig status.

## Environment Variables
- `PORT`: Port to run web server (default `3000`)
- `BACKEND_URL`: Internal URL for the Backend Kubernetes Service (default `http://backend-service:5000`)
- `POD_NAME`: Name of the frontend Kubernetes pod (`metadata.name`)
- `NODE_AZ`: Availability Zone of the frontend node
