#!/bin/bash

GITREPO='git@github.com:sre2go/majestix.git'
SSHPRIVATEKEY=$(cat ~/.ssh/id_rsa | base64)

# Step 1: Install ArgoCD
echo "Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 6.11.1 --namespace argocd --create-namespace

# Step 2: Wait for ArgoCD to be ready
echo "Waiting for ArgoCD components to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# Step 4: Retrieve the initial admin password
echo "Retrieving the initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)
echo "ArgoCD initial password: $ARGOCD_PASSWORD"

# Step 6: Create App-of-Apps Repository secret
echo "Creating the App-of-Apps repo secret..."
cat <<EOF > secret-app-of-apps.yaml
apiVersion: v1
kind: Secret
metadata:
  annotations:
    managed-by: argocd.argoproj.io
  labels:
    argocd.argoproj.io/secret-type: repository
  name: repo-app-of-apps
  namespace: argocd
type: Opaque
data:
  name: $(echo -n "app-of-apps" | base64)
  project: $(echo -n "*" | base64)
  sshPrivateKey: |
$(echo "$SSHPRIVATEKEY" | sed 's/^/    /')
  type: $(echo -n "git" | base64)
  url: $(echo -n "$GITREPO" | base64)
EOF

kubectl apply -f secret-app-of-apps.yaml


# Step 7: Create the App-of-Apps manifest
echo "Creating the App-of-Apps manifest..."
cat <<EOF > app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: '${GITREPO}'
    targetRevision: HEAD
    path: 'apps'
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

kubectl apply -f app-of-apps.yaml

echo "Bootstrap complete. ArgoCD is installed and configured to manage itself using the App-of-Apps approach."
