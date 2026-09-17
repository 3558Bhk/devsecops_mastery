# Kubernetes Commands - SDE3 Revision

## Cluster Info
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get ns
kubectl config get-contexts
kubectl config use-context prod
kubectl version
```

## Pods
```bash
kubectl get pods
kubectl get pods -A
kubectl get pods -o wide -n default
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs -f <pod-name> -c <container>
kubectl logs --previous <pod-name> # crashed
kubectl exec -it <pod-name> -- bash
kubectl delete pod <pod-name>
kubectl run nginx --image=nginx --restart=Never
```

## Deployments
```bash
kubectl get deployments
kubectl get deploy
kubectl create deployment myapp --image=myapp:1.0 --replicas=3
kubectl scale deployment myapp --replicas=5
kubectl set image deployment/myapp myapp=myapp:2.0
kubectl rollout status deployment/myapp
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp
kubectl rollout undo deployment/myapp --to-revision=2
kubectl describe deployment myapp
```

## Services & Networking
```bash
kubectl get svc
kubectl get svc -A
kubectl expose deployment myapp --type=LoadBalancer --port=80 --target-port=3000
kubectl port-forward svc/myapp 8080:80
kubectl get ingress -A
```

## Config & Secrets
```bash
kubectl get configmaps
kubectl get secrets
kubectl create configmap app-config --from-literal=ENV=prod
kubectl create secret generic db-secret --from-literal=password=secret123
kubectl describe configmap app-config
kubectl get secret db-secret -o yaml
```

## Manifests
```bash
kubectl apply -f deployment.yaml
kubectl delete -f deployment.yaml
kubectl get all -n default
kubectl apply -f . # apply all in folder
kubectl diff -f deployment.yaml
kubectl edit deployment myapp
```

## Debugging SDE3
```bash
kubectl top nodes
kubectl top pods
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl get events -w
kubectl describe node <node>
kubectl get pods --field-selector=status.phase=Failed
kubectl auth can-i create deployments --as=dev-user
```

## Helm
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-release bitnami/nginx
helm list
helm upgrade my-release bitnami/nginx --set replicaCount=3
helm rollback my-release 1
helm uninstall my-release
```

## YAML Quick Ref
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: myapp}
spec:
  replicas: 3
  selector: {matchLabels: {app: myapp}}
  template:
    metadata: {labels: {app: myapp}}
    spec:
      containers:
      - name: myapp
        image: myapp:1.0
        ports: [{containerPort: 3000}]
        envFrom: [{configMapRef: {name: app-config}}]
        livenessProbe: {httpGet: {path: /health, port: 3000}, initialDelaySeconds: 30}
        resources: {limits: {cpu: "500m", memory: "512Mi"}, requests: {cpu: "250m", memory: "256Mi"}}
```
