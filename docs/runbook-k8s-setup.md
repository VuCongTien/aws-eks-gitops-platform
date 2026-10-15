# 🚀 Runbook: Cấu hình Kubernetes sau Terraform Apply

> **Điều kiện tiên quyết**: Terraform đã `apply` thành công, EKS Cluster và Node Group đã ở trạng thái `ACTIVE` / `READY`.

---

## BƯỚC 0: Lấy các Output từ Terraform

```bash
# Lấy toàn bộ output của Terraform (VPC ID, Cluster Name, Role ARNs...)
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks
terraform output
```

> Ghi lại các giá trị: `vpc_id`, `cluster_name`, `alb_controller_role_arn`, `backend_app_role_arn`

---

## BƯỚC 1: Kết nối kubectl vào EKS Cluster

```bash
# Cập nhật kubeconfig trỏ vào cluster mới
aws eks update-kubeconfig --region ap-southeast-1 --name my-cluster

# Xác minh IAM identity đang dùng (phải trùng với identity đã tạo cluster)
aws sts get-caller-identity

# Kiểm tra các Nodes đã Ready chưa
kubectl get nodes
```

✅ **Kết quả cần thấy**: Các Nodes ở trạng thái `Ready`.

---

## BƯỚC 2: Lấy VPC ID (dùng cho Bước 3)

```bash
VPC_ID=$(aws eks describe-cluster \
  --name my-cluster \
  --region ap-southeast-1 \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo "VPC_ID = $VPC_ID"
```

---

## BƯỚC 3: Cài AWS Load Balancer Controller

```bash
# 3.1 Thêm Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# 3.2 Cài đặt ALB Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=lab-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::793239960568:role/AmazonEKSLoadBalancerControllerRole" \
  --set region=ap-southeast-1 \
  --set vpcId=$VPC_ID

# 3.3 Kiểm tra Pods ALB Controller đã Running chưa
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

✅ **Kết quả cần thấy**: 2 Pods đều báo `1/1 Running`.

---

## BƯỚC 4: Cài Secrets Store CSI Driver

```bash
# 4.1 Thêm Helm repos
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

# 4.2 Cài CSI Driver (bật syncSecret và tokenRequests cho IRSA)
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --set 'tokenRequests[0].audience=sts.amazonaws.com'

# 4.3 Kiểm tra CSI Driver DaemonSet đã chạy chưa
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
```

✅ **Kết quả cần thấy**: 1 Pod `Running` trên mỗi Worker Node (DaemonSet).

---

## BƯỚC 5: Cài AWS Secrets Manager Provider (Plugin cho CSI)

```bash
# Dùng manifest chính thức từ AWS (tránh conflict ServiceAccount với Helm)
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# Kiểm tra Provider DaemonSet
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws
```

✅ **Kết quả cần thấy**: 1 Pod `Running` trên mỗi Worker Node.

---

## BƯỚC 6: Build & Push Docker Images lên ECR

```bash
# 6.1 Login Docker vào ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin 793239960568.dkr.ecr.ap-southeast-1.amazonaws.com

# 6.2 Build & Push Backend
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-app/apps/backend
docker build -t 793239960568.dkr.ecr.ap-southeast-1.amazonaws.com/backend:latest .
docker push 793239960568.dkr.ecr.ap-southeast-1.amazonaws.com/backend:latest

# 6.3 Build & Push Frontend
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-app/apps/frontend
docker build -t 793239960568.dkr.ecr.ap-southeast-1.amazonaws.com/frontend:latest .
docker push 793239960568.dkr.ecr.ap-southeast-1.amazonaws.com/frontend:latest
```

---

## BƯỚC 7: Deploy Backend & Frontend qua Helm

```bash
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-infra/helm
kubectl create namespace backend-ns
kubectl create namespace frontend-ns

helm install backend-app ./backend -n backend-ns
helm install frontend-app ./frontend -n frontend-ns

# 7.3 Kiểm tra Pods đang chạy
kubectl get pods -w
```

✅ **Kết quả cần thấy**: Tất cả pods `1/1 Running`.

---

## BƯỚC 8: Lấy URL Công Khai của Ứng Dụng (Ingress ALB)

```bash
# Chờ khoảng 1-2 phút cho ALB Controller tạo Load Balancer
kubectl get ingress

# Khi cột ADDRESS xuất hiện URL, chạy lệnh này để lấy nhanh:
kubectl get ingress frontend-app-frontend-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

✅ **Kết quả cần thấy**: URL dạng `k8s-default-frontend-xxx.ap-southeast-1.elb.amazonaws.com`

---

## 🔧 Lệnh Debug & Kiểm Tra Nhanh (dùng khi có lỗi)

```bash
# Xem log ALB Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=30

# Xem Events của cả cluster (debug pod lỗi)
kubectl get events --sort-by='.metadata.creationTimestamp' | tail -n 20

# Xem chi tiết 1 Pod đang lỗi
kubectl describe pod <tên-pod>

# Xem log của Backend app
kubectl logs -l app=backend --tail=20

# Kiểm tra HPA
kubectl get hpa

# Helm list tất cả releases
helm list -A
```

---

## ⏸️ Tắt/Bật để Tiết Kiệm Chi Phí

### Tắt (khi nghỉ):
```
1. EKS Console > Cluster > Compute > Node group > Edit > Desired: 0, Min: 0
2. RDS Console > Actions > Stop temporarily
```

### Bật lại (khi làm tiếp):
```bash
# Sau khi Start RDS và tăng Node Group lên (Desired: 3, Min: 2)
# Kiểm tra lại:
kubectl get nodes
kubectl get pods
```
