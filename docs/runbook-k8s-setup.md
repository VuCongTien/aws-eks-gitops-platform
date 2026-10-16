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
kubectl get ingress -n frontend-ns

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

---

## PHASE 2 — STEP 1: Preflight trước khi cài ArgoCD

Mục tiêu: xác nhận phiên bản EKS, quyền Kubernetes và tài nguyên node trước khi cài ArgoCD. Các lệnh dưới đây chỉ đọc trạng thái; chúng chưa tạo namespace, CRD, Helm release hay workload nào.

```bash
aws eks describe-cluster \
  --name my-cluster \
  --region ap-southeast-1 \
  --query "cluster.{version:version,status:status}" \
  --output table

kubectl auth can-i create namespaces
kubectl auth can-i create customresourcedefinitions.apiextensions.k8s.io
kubectl auth can-i create clusterroles.rbac.authorization.k8s.io

kubectl top nodes
kubectl describe nodes
```

### Cách xác minh

- Cluster cần ở trạng thái `ACTIVE`; ghi lại phiên bản Kubernetes.
- Ba lệnh `kubectl auth can-i` cần trả về `yes` để cài ArgoCD và các CRD cần thiết.
- `kubectl top nodes` hiển thị CPU/RAM đang sử dụng. Nếu lệnh báo không có Metrics API, kiểm tra mục `Allocated resources` trong kết quả `kubectl describe nodes`.
- Chỉ chuyển sang bước cài đặt sau khi đã xem các kết quả trên và xác nhận cluster có đủ quyền cùng tài nguyên.

### Ghi nhận preflight hiện tại

Kết quả kiểm tra: EKS `my-cluster` đang `ACTIVE` ở Kubernetes `1.36`; các quyền tạo namespace, CRD và ClusterRole đều trả về `yes`. Lần kiểm tra tiếp theo, `kubectl describe nodes` liệt kê ba worker nodes với `Ready=True`, không có MemoryPressure hoặc DiskPressure. `kubectl top nodes` vẫn báo không có Metrics API; đây là giới hạn đo metrics, không đồng nghĩa node không hoạt động. Các node hiện có workload và đủ điều kiện để tiếp tục cài ArgoCD.

Chạy các lệnh chỉ đọc sau để kiểm tra trạng thái EKS node group và workload:

```bash
aws eks list-nodegroups \
  --cluster-name my-cluster \
  --region ap-southeast-1 \
  --output table

# Terraform hiện khai báo node group tên my-node-group.
# Nếu lệnh trên trả về tên khác, thay tên bên dưới bằng đúng tên đã trả về.
aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-node-group \
  --region ap-southeast-1 \
  --query "nodegroup.{status:status,desired:scalingConfig.desiredSize,min:scalingConfig.minSize,max:scalingConfig.maxSize,issues:health.issues}" \
  --output yaml

kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
```

Cách xác minh: node group cần ở trạng thái `ACTIVE`, desired capacity lớn hơn `0`, và `kubectl get nodes` cần liệt kê worker nodes ở trạng thái `Ready`. Nếu chưa đạt, xử lý node group trước rồi mới quay lại bước cài ArgoCD.
---

## PHASE 2 — STEP 2: Cài ArgoCD bằng Helm

Mục tiêu: cài ArgoCD vào namespace riêng `argocd`. Bước này chỉ cài các thành phần ArgoCD; chưa khai báo Application, chưa để ArgoCD quản lý hai Helm release đang chạy và chưa bật auto-sync.

Chart `argo/argo-cd` do cộng đồng duy trì. Dùng phiên bản chart được pin để lần cài đặt có thể lặp lại: chart `10.10.3`, ứng dụng Argo CD `v3.5.5`. Metadata chart khai báo Kubernetes từ `1.25.0` trở lên; EKS hiện tại là `1.36`. [Thông tin chart](https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/Chart.yaml) · [Tài liệu cài đặt Argo CD](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/installation.md)

```bash
# Thêm/cập nhật repository Helm chính thức của project argo-helm
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

# Xác nhận metadata chart trước khi cài
helm show chart argo/argo-cd --version 10.10.3

# Cài ArgoCD; --wait chờ các workload sẵn sàng, tối đa 15 phút
helm upgrade --install argocd argo/argo-cd \
  --version 10.10.3 \
  --namespace argocd \
  --create-namespace \
  --wait \
  --timeout 15m
```

### Cách xác minh

```bash
helm status argocd --namespace argocd
kubectl get pods --namespace argocd
kubectl get crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

Cần thấy Helm release `argocd` ở trạng thái `deployed`, các pod trong namespace `argocd` ở trạng thái `Running`/`Ready`, và ba CRD của Argo CD đã được đăng ký. Nếu lệnh cài đặt timeout hoặc pod không `Ready`, dừng ở đây và gửi lỗi cùng kết quả `kubectl get pods -n argocd` và `kubectl describe pods -n argocd`; chưa tiếp tục tạo Application.
### Kết quả cài đặt đã xác minh

Ngày 2026-10-16, Helm release `argocd` cài thành công với chart `10.10.3` / Argo CD `v3.5.5`, trạng thái `deployed`, revision `1`. Các pod controller, server, repo-server, Redis, Dex, ApplicationSet và notifications đều `1/1 Running`; pod `argocd-redis-secret-init` ở trạng thái `Completed` là bình thường. Ba CRD `applications.argoproj.io`, `applicationsets.argoproj.io` và `appprojects.argoproj.io` đã tồn tại.

---

## PHASE 2 — STEP 3: Truy cập UI ArgoCD qua port-forward

Mục tiêu: mở UI từ máy local mà không tạo LoadBalancer hoặc public endpoint. Giữ port-forward chỉ chạy trên localhost; không chia sẻ mật khẩu admin trong chat.

Mở terminal thứ nhất và để lệnh này chạy:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Mở terminal thứ hai để lấy mật khẩu khởi tạo và chỉ dùng nó trực tiếp trên máy của bạn:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Mở `https://localhost:8080` trong browser, chấp nhận cảnh báo chứng chỉ tự ký cho kết nối local, rồi đăng nhập bằng username `admin` và mật khẩu vừa lấy. Argo CD hướng dẫn dùng port-forward tới service port `443` để truy cập local; chart cũng ghi nhận cách này trong phần NOTES. [Argo CD: Access the API Server](https://argo-cd.readthedocs.io/en/latest/getting_started/#3-access-the-argo-cd-api-server)

### Cách xác minh

- Terminal port-forward hiện `Forwarding from 127.0.0.1:8080 -> ...` và vẫn chạy.
- UI hiện trang ArgoCD và đăng nhập được bằng tài khoản `admin`.
- Chưa tạo Application ở bước này; danh sách Applications sẽ còn trống.
- Không gửi mật khẩu khởi tạo vào chat. Dừng port-forward bằng `Ctrl+C` khi muốn đóng phiên truy cập.
### Kết quả truy cập UI đã xác minh

Người dùng xác nhận đăng nhập UI ArgoCD thành công qua port-forward local.

---

## PHASE 3 — STEP 1: Kết nối GitOps repository vào ArgoCD

Project hiện có hai GitHub repository riêng: app source `https://github.com/VuCongTien/my-app-v1.git` và infra/GitOps `https://github.com/VuCongTien/aws-eks-gitops-platform.git`. ArgoCD cần đọc repository infra vì hai Helm chart hiện nằm tại `helm/backend` và `helm/frontend` trong repository đó. Điều này chưa tạo Application hay thay đổi release đang chạy.

Trong ArgoCD UI:

1. Mở **Settings → Repositories → Connect Repo**.
2. Chọn kết nối **Via HTTPS**.
3. Điền repository URL `https://github.com/VuCongTien/aws-eks-gitops-platform.git`.
4. Nếu repository public, để trống username/password rồi chọn **Connect**. Nếu GitHub báo cần xác thực, dừng lại; không gửi token hoặc password qua chat.

### Cách xác minh

- Repository xuất hiện trong danh sách Settings → Repositories với trạng thái kết nối thành công.
- Nếu trạng thái lỗi, ghi lại nội dung lỗi (đã che thông tin nhạy cảm) để xử lý quyền truy cập trước khi tạo Application.
- Chưa tạo ArgoCD Application và chưa bật auto-sync ở bước này.
### Kết quả kết nối GitOps repository đã xác minh

Người dùng xác nhận ArgoCD hiển thị repository `https://github.com/VuCongTien/aws-eks-gitops-platform` với Connection Status `Successful`.

---

## PHASE 3 — STEP 2: Kiểm tra Helm charts render trước khi tạo Application

Mục tiêu: kiểm tra cú pháp và render hai Helm chart bằng đúng release name/namespace hiện đang chạy. Các lệnh này chỉ render YAML trên máy local, không gửi thay đổi lên EKS và không chuyển quyền quản lý workload cho ArgoCD.

Chạy trong WSL:

```bash
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-infra

helm lint ./helm/backend
helm template backend-app ./helm/backend --namespace backend-ns \
  > /tmp/backend-rendered.yaml

helm lint ./helm/frontend
helm template frontend-app ./helm/frontend --namespace frontend-ns \
  > /tmp/frontend-rendered.yaml
```

Có thể kiểm tra nhanh các resource name/namespace được render:

```bash
grep -nE '^(kind:|  name:|  namespace:)' /tmp/backend-rendered.yaml

grep -nE '^(kind:|  name:|  namespace:)' /tmp/frontend-rendered.yaml
```

### Cách xác minh

- Cả hai lệnh `helm lint` kết thúc thành công, không có lỗi chart/template.
- Hai lệnh `helm template` kết thúc thành công và tạo hai file YAML trong `/tmp`.
- Tên Deployment cần khớp workload hiện tại: `backend-app-backend` trong `backend-ns` và `frontend-app-frontend` trong `frontend-ns`.
- Chưa tạo ArgoCD Application, chưa bấm Sync và chưa bật auto-sync. Gửi lỗi lint/template hoặc phần tên resource nếu có khác biệt; ta sẽ xử lý trước khi chuyển giao quản lý.
### Kết quả lint/render đã xác minh

Người dùng chạy `helm lint` cho cả hai chart; mỗi chart có `0 chart(s) failed` (chỉ có khuyến nghị tùy chọn về icon). Cả hai lệnh `helm template` đều hoàn tất. Tên Deployment/Service khớp release hiện tại: backend `backend-app-backend` trong `backend-ns`, frontend `frontend-app-frontend` trong `frontend-ns`. Backend còn render ClusterRole và ClusterRoleBinding; cần so sánh manifest trước khi cho ArgoCD sync để tránh chuyển quyền quản lý ngoài dự kiến.

---

## PHASE 3 — STEP 3: So sánh manifest Helm đang chạy với chart hiện tại

Mục tiêu: xác nhận chart ở Git render cùng cấu hình với manifest đã cài bằng Helm. Các lệnh chỉ đọc release metadata, ghi bản so sánh vào `/tmp`, và không thay đổi EKS.

```bash
helm get manifest backend-app --namespace backend-ns \
  > /tmp/backend-installed-helm.yaml
helm get manifest frontend-app --namespace frontend-ns \
  > /tmp/frontend-installed-helm.yaml

diff -u /tmp/backend-installed-helm.yaml /tmp/backend-rendered.yaml
diff -u /tmp/frontend-installed-helm.yaml /tmp/frontend-rendered.yaml
```

### Cách xác minh

- Nếu `diff` không in gì và trả về exit code `0`, nội dung manifest đã cài bằng Helm khớp với chart hiện tại.
- Nếu có khác biệt, chưa tạo/sync ArgoCD Application. Gửi phần diff để phân tích; trước khi chia sẻ, rà lại và che mọi thông tin nhạy cảm.
- Bước này chưa thay đổi Helm release ownership và chưa bật auto-sync.
### Kết quả so sánh Helm manifest đã xác minh

Người dùng chạy `helm get manifest` và so sánh với hai file đã render. Khác biệt hiển thị chỉ là dòng trống ở cuối resource/document; không thấy khác biệt nội dung cấu hình.

---

## PHASE 3 — STEP 4: So sánh chart với trạng thái live trên EKS

Mục tiêu: xem các thay đổi mà `kubectl apply` cần để đưa resource live khớp với YAML render. `kubectl diff` dùng dry-run để chỉ hiển thị khác biệt, không ghi cấu hình lên cluster.

```bash
kubectl diff -f /tmp/backend-rendered.yaml
kubectl diff -f /tmp/frontend-rendered.yaml
```

### Cách xác minh

- Exit code `0`: không có khác biệt giữa resource live và YAML dự kiến.
- Exit code `1`: có khác biệt; đây là kết quả diff, không phải lỗi của kubectl. Đọc các dòng `+`/`-` và gửi phần khác biệt để xem xét trước khi tạo/sync Application.
- Exit code lớn hơn `1`, hoặc lỗi authorization/API: gửi thông báo lỗi để xử lý.
- Chưa tạo Application, chưa sync và chưa bật auto-sync ở bước này.

Tham khảo: [Kubernetes kubectl diff](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_diff/).
### Kết quả so sánh với trạng thái live đã xác minh

Người dùng chạy `kubectl diff` cho cả backend và frontend; không có output khác biệt. Điều này cho thấy resource live khớp YAML render theo phép so sánh này. Chưa có thay đổi nào được áp dụng lên workload.

---

## PHASE 3 — STEP 5: Đăng ký riêng ArgoCD Application backend (chưa Sync)

Mục tiêu: tạo đúng một ArgoCD Application để ArgoCD đọc chart backend và hiển thị trạng thái/diff. Manifest không có `syncPolicy.automated`, nên ArgoCD không tự áp dụng chart. Chưa bấm nút **Sync**.

Manifest đã chuẩn bị tại `kubernetes/argocd/applications/backend.yaml` với các giá trị đã kiểm tra: repo GitOps trên nhánh `main`, chart `helm/backend`, Helm release `backend-app`, namespace `backend-ns`.

Từ thư mục gốc repo infra, áp dụng duy nhất Application CR:

```bash
kubectl apply -f kubernetes/argocd/applications/backend.yaml
```

### Cách xác minh

```bash
kubectl get application backend-app -n argocd
```

Mở Application `backend-app` trong UI để xem resource tree và trạng thái Sync/Health. Không bấm **Sync**, không bật auto-sync, và không xóa Helm release. Gửi trạng thái hiển thị cùng mọi khác biệt ArgoCD báo trước khi chuyển giao quản lý.
### Kết quả đăng ký backend Application

Người dùng đã chạy `kubectl apply -f kubernetes/argocd/applications/backend.yaml`; Application `backend-app` được tạo. ArgoCD hiện báo `OutOfSync` / `Degraded`, và UI xác nhận auto-sync đang tắt. Chưa bấm **Sync**. Cần kiểm tra lý do health và diff do ArgoCD tính toán trước khi quyết định chuyển giao resource.

Chẩn đoán chỉ đọc:

```bash
kubectl get application backend-app -n argocd \
  -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.message}{"\n"}{end}'

kubectl describe hpa backend-app-backend -n backend-ns
kubectl get hpa backend-app-backend -n backend-ns
```

Trong UI, bấm **DIFF** để xem khác biệt ArgoCD phát hiện; không bấm **SYNC**. Gửi nội dung conditions, kết quả HPA và phần diff (che thông tin nhạy cảm nếu có). Nguyên nhân chưa được kết luận cho đến khi xem các kết quả này.
### Chẩn đoán Application OutOfSync/Degraded

Ảnh DIFF của người dùng cho thấy các khác biệt đang hiển thị là annotation `argocd.argoproj.io/tracking-id` mà ArgoCD thêm để theo dõi resource; chưa thấy thay đổi `spec` trong các ảnh. Đây là phần metadata của bước chuyển giao quản lý, chưa được Sync.

HPA `backend-app-backend` đang `ScalingActive=False`, reason `FailedGetResourceMetric`, vì API `pods.metrics.k8s.io` chưa tồn tại. CPU target hiện là `<unknown>/50%`, nên HPA không thể tự động scale và ArgoCD đánh dấu HPA/ứng dụng `Degraded`. Đây là lỗi metrics hiện có trên cluster, không phải lỗi render của chart.

Kiểm tra read-only trước khi quyết định cài Metrics Server:

```bash
aws eks list-addons \
  --cluster-name my-cluster \
  --region ap-southeast-1 \
  --output table

aws eks describe-addon-versions \
  --addon-name metrics-server \
  --kubernetes-version 1.36 \
  --region ap-southeast-1 \
  --query 'addons[0].addonVersions[].addonVersion' \
  --output table

kubectl get apiservice v1beta1.metrics.k8s.io
```

Chưa bấm **Sync** và chưa cài/xóa addon. Xác nhận Metrics Server chưa có và kiểm tra bản tương thích trước khi xử lý HPA; sau đó quay lại đánh giá thao tác Sync thủ công.
### Kết quả kiểm tra Metrics Server

Người dùng xác nhận danh sách EKS add-on hiện trống và `v1beta1.metrics.k8s.io` chưa được đăng ký. AWS EKS trả về `v0.9.0-eksbuild.13` là bản Metrics Server tương thích với Kubernetes `1.36` tại region hiện tại.

---

## PHASE 3 — STEP 6: Quản lý Metrics Server bằng Terraform

Metrics Server cung cấp Resource Metrics API cho HPA. Add-on được khai báo trong `Terraform/eks.tf` dưới dạng `aws_eks_addon.metrics_server`, dùng đúng version tương thích đã kiểm tra (`v0.9.0-eksbuild.13`). Terraform tham chiếu trực tiếp EKS cluster và phụ thuộc node group, nên thứ tự tạo là cluster → node group → add-on; khi destroy, Terraform xóa add-on trước node group và cluster. Xem [tài liệu resource aws_eks_addon của Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon).

Không tạo add-on bằng `aws eks create-addon`, vì tài nguyên tạo ngoài Terraform sẽ không tự có trong Terraform state. Nếu add-on được tạo ngoài Terraform, cần import vào state trước khi quản lý bằng Terraform.

Tại máy quản lý, chạy bước kiểm tra trước:

```bash
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-infra/Terraform
terraform fmt -check
terraform validate
```

Trong lần đầu quản lý add-on, kiểm tra state trước khi apply. Nếu add-on đã có ngoài Terraform, import nó vào đúng state thay vì tạo resource trùng:

```bash
terraform state list | grep 'aws_eks_addon.metrics_server'
terraform plan
```

Nếu `terraform state list` không tìm thấy resource nhưng add-on đang tồn tại trong AWS, sao lưu state rồi import vào đúng state/workspace bằng `terraform import aws_eks_addon.metrics_server my-cluster:metrics-server`, sau đó chạy lại `terraform plan`. Nếu plan chỉ ra thay đổi ngoài dự kiến, dừng lại để kiểm tra; chỉ chạy `terraform apply` khi plan đã được xem xét. `terraform destroy` chỉ quản lý những resource có trong đúng Terraform configuration và state/workspace đang dùng. Resource này phụ thuộc node group và cluster, vì vậy Terraform sẽ xóa add-on trước node group và cluster. Không chạy destroy chỉ để kiểm tra.

Sau khi apply hoàn tất, kiểm tra add-on và Metrics API/HPA:

```bash
aws eks describe-addon \
  --cluster-name my-cluster \
  --addon-name metrics-server \
  --region ap-southeast-1 \
  --query 'addon.{status:status,version:addonVersion,issues:health.issues}' \
  --output yaml

kubectl get deployment metrics-server -n kube-system
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl get hpa backend-app-backend -n backend-ns
```

### Cách xác minh

- Add-on ở trạng thái `ACTIVE`, deployment `metrics-server` có pod `Available`.
- APIService `v1beta1.metrics.k8s.io` báo `Available=True`; `kubectl top nodes` trả về CPU/RAM.
- HPA hiện giá trị CPU thay cho `<unknown>`. Nếu vừa cài xong, đợi một chu kỳ scrape metrics rồi kiểm tra lại.
- Chưa bấm Sync trong ArgoCD. Sau khi HPA hoạt động, đánh giá lại Health và thực hiện chuyển giao resource bằng manual Sync riêng.

### Kết quả Metrics Server và Terraform state đã xác minh

Người dùng xác nhận add-on `metrics-server` ở trạng thái `ACTIVE`, version `v0.9.0-eksbuild.13`, không có health issue; Deployment có `2/2` pod sẵn sàng; APIService `v1beta1.metrics.k8s.io` là `Available=True`; `kubectl top nodes` trả metrics; HPA backend đọc CPU `1%/50%`. Kiểm tra state file local trong `Terraform/terraform.tfstate` thấy resource `aws_eks_addon.metrics_server` với ID `my-cluster:metrics-server` và version khớp. Vì vậy không cần import theo state snapshot này. Trước khi dựa vào state để destroy, xác nhận bằng `terraform state list` và `terraform plan` trong WSL, đúng thư mục/workspace đang dùng.

Người dùng đã chạy `terraform apply`. Sau đó ArgoCD hiển thị Application `backend-app` là `Healthy` nhưng vẫn `OutOfSync`; auto-sync vẫn tắt và có 8 resource OutOfSync. Trước đó DIFF cho thấy thay đổi là annotation `argocd.argoproj.io/tracking-id` để ArgoCD theo dõi resource hiện có. Bước tiếp theo là rà lại DIFF rồi thực hiện manual Sync để ghi nhận tracking annotation; chưa bật auto-sync.

Người dùng đã rà DIFF và manual Sync `backend-app` thành công. UI xác nhận `Healthy`, `Synced`, `Sync OK`; auto-sync vẫn tắt. Khác biệt trước Sync chỉ là tracking annotation. Application frontend được chuẩn bị riêng ở `kubernetes/argocd/applications/frontend.yaml` với repo GitOps, chart `helm/frontend`, release `frontend-app` và namespace `frontend-ns`; manifest chưa được apply.

### PHASE 3 — STEP 7: Đăng ký ArgoCD Application frontend (chưa Sync)

Manifest `kubernetes/argocd/applications/frontend.yaml` đã khai báo frontend chart trong GitOps repo, dùng release `frontend-app` và namespace `frontend-ns`. Chưa tạo Application, chưa Sync, chưa bật auto-sync.

Từ thư mục gốc repo infra:

```bash
kubectl apply -f kubernetes/argocd/applications/frontend.yaml
kubectl get application frontend-app -n argocd
```

Kiểm tra trạng thái và **DIFF** trong ArgoCD UI trước khi Sync. Chỉ tiếp tục nếu khác biệt dự kiến là tracking annotation như backend; không bấm Sync nếu có khác biệt cấu hình workload chưa được giải thích. Giữ auto-sync tắt.

Người dùng đã kiểm tra DIFF: Service, Deployment, HPA và Ingress chỉ có thay đổi annotation `argocd.argoproj.io/tracking-id`. Sau manual Sync, UI xác nhận frontend `Healthy`, `Synced`, `Sync OK`; auto-sync vẫn tắt. Backend và frontend hiện đã được ArgoCD theo dõi từ GitOps repo.

---

## PHASE 4 — CI/CD: GitHub Actions → ECR → GitOps PR → ArgoCD

Hai repo app và GitOps được tối ưu cho luồng tách biệt: app repo `VuCongTien/my-app-v1`; GitOps repo `VuCongTien/aws-eks-gitops-platform`. Workflow tại `Long-lab-aws-eks-app/.github/workflows/app-ci-cd.yml` build hai Docker image khi có PR, và khi merge/push lên `main` thì dùng GitHub OIDC để push tag `sha-<commit-sha>-<run-attempt>` vào ECR. Sau đó workflow tạo/cập nhật PR trong GitOps repo để đổi tag cho cả hai Helm chart. Merge PR là release approval; ArgoCD auto-sync triển khai tag mới. ECR repository dùng immutable tags; lifecycle policy giữ 10 image version-tagged, giữ 10 image CI-tagged gần nhất, đồng thời xóa image không tag sau 7 ngày.

IAM role `github-actions-ecr-push` chỉ được assume từ app repo trên branch `main`; policy chỉ cho phép push vào hai ECR repo của project. GitHub OIDC provider dùng audience `sts.amazonaws.com`; subject được khóa theo repository ID `1418957504`, owner ID `217227847`, và branch `main`. Tham khảo [GitHub OIDC cho AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) và [IAM permissions cho ECR push](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html).

### Bước 1: Review và apply Terraform cho GitHub OIDC/ECR

Trong WSL:

```bash
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-infra/Terraform
terraform fmt -check
terraform validate
terraform plan
```

Plan dự kiến thêm GitHub IAM OIDC provider, IAM role và policy; đổi ECR tag mutability từ `MUTABLE` sang `IMMUTABLE`; thêm lifecycle rule dọn các SHA tags của CI, giữ nguyên rule cho image tag bắt đầu bằng `v` và rule dọn image không tag. Dừng lại nếu plan đòi xóa/thay thế EKS, RDS, VPC hoặc resource không liên quan. Chỉ sau khi xem plan mới chạy:

```bash
terraform apply
terraform output -raw github_actions_ecr_role_arn
```

### Bước 2: Thêm GitHub variable và secret

Trong Settings → Secrets and variables → Actions của `VuCongTien/my-app-v1`:

- Repository variable `AWS_ECR_ROLE_ARN`: giá trị từ output `github_actions_ecr_role_arn`.
- Repository secret `GITOPS_TOKEN`: fine-grained token chỉ có quyền vào `aws-eks-gitops-platform`, với `Contents: Read and write` và `Pull requests: Read and write`. Không đưa token vào file hay workflow log.

### Bước 3: Bật ArgoCD auto-sync

Application manifests backend/frontend được cập nhật với `automated`, `selfHeal: true`, `prune: false`. ArgoCD tự triển khai thay đổi đã merge trong GitOps repo và sửa drift do thay đổi thủ công; `prune: false` giữ resource nếu manifest bị xóa. Commit/copy manifest lên GitOps repo, sau đó apply tại WSL:

```bash
cd /mnt/d/Fsoft/Cloud/CloudAWS/Long-lab-aws-eks/Long-lab-aws-eks-infra
kubectl apply -f kubernetes/argocd/applications/backend.yaml
kubectl apply -f kubernetes/argocd/applications/frontend.yaml
kubectl get applications -n argocd
```

### Bước 4: Kích hoạt và xác minh luồng

Commit workflow vào `main` của app repo. PR app chạy build-only; push lên `main` build/push image và tạo PR cập nhật GitOps. Review diff PR, xác nhận hai image tag cùng commit/run attempt, rồi merge. ArgoCD sẽ tự sync; kiểm tra:

```bash
kubectl get applications -n argocd
kubectl rollout status deployment/backend-app-backend -n backend-ns
kubectl rollout status deployment/frontend-app-frontend -n frontend-ns
kubectl get pods -n backend-ns -o wide
kubectl get pods -n frontend-ns -o wide
```

Workflow chỉ push image sau khi PR app được merge và chỉ tạo GitOps PR sau khi push cả hai image thành công. Rollback bằng cách revert GitOps PR/commit để trả chart về image tag trước; ArgoCD sẽ triển khai lại tag đó.
