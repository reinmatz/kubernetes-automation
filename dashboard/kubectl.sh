helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 &
# open chrome with https://localhost:8443
kubectl config set-context docker-desktop --namespace kubernetes-dashboard
kubectl get sa
oc adm policy add-cluster-role-to-user cluster-admin -z kubernetes-dashboard-kong
kubectl create token kubernetes-dashboard-kong
