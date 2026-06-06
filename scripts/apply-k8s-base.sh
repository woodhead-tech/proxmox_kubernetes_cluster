#!/usr/bin/env bash
# apply-k8s-base.sh - Apply base Kubernetes manifests after cluster bootstrap
#
# This script applies foundational K8s resources:
#   1. Base namespaces (apps, ingress-system, monitoring)
#   2. MetalLB for LoadBalancer service support (optional)
#
# Prerequisites:
#   - Talos cluster bootstrapped (make bootstrap)
#   - kubeconfig available at talos/_out/kubeconfig
#
# Usage: ./scripts/apply-k8s-base.sh [--with-metallb]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${REPO_ROOT}/k8s/base"

# Use the generated kubeconfig if KUBECONFIG is not set
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/talos/_out/kubeconfig}"

INSTALL_METALLB=false
METALLB_VERSION="v0.14.9"

# --- Parse flags ---
for arg in "$@"; do
  case ${arg} in
    --with-metallb) INSTALL_METALLB=true ;;
    *) echo "Usage: $0 [--with-metallb]" && exit 1 ;;
  esac
done

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Verify cluster access ---
log "Verifying cluster access..."
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot connect to the cluster. Is KUBECONFIG set correctly?"
  echo "  Expected: ${KUBECONFIG}"
  exit 1
fi

# --- Apply base namespaces ---
log "Applying base namespaces..."
kubectl apply -f "${K8S_DIR}/namespace.yml"

# --- Kubelet CSR auto-approver (always apply) ---
log "Applying kubelet CSR auto-approver..."
kubectl apply -f "${K8S_DIR}/kubelet-csr-approver.yml" 2>/dev/null || true

# --- MetalLB (optional) ---
if [[ "${INSTALL_METALLB}" == "true" ]]; then
  log "Installing MetalLB ${METALLB_VERSION}..."
  kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

  # Wait for MetalLB pods to be ready before applying config
  log "Waiting for MetalLB controller to be ready..."
  kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=120s 2>/dev/null || true

  log "Applying MetalLB IP pool configuration..."
  kubectl apply -f "${K8S_DIR}/metallb/namespace.yml"

  # Retry IP pool apply — MetalLB webhook may need time to be ready after fresh bootstrap.
  # If it fails due to webhook timeout, temporarily remove and re-add the webhook config.
  if ! kubectl apply -f "${K8S_DIR}/metallb/ip-pool.yml" 2>/dev/null; then
    log "Webhook not ready — bypassing temporarily to apply IP pool..."
    kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o yaml > /tmp/metallb-webhook-backup.yaml 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration 2>/dev/null || true
    kubectl apply -f "${K8S_DIR}/metallb/ip-pool.yml"
    if [[ -f /tmp/metallb-webhook-backup.yaml ]]; then
      kubectl apply -f /tmp/metallb-webhook-backup.yaml
      rm -f /tmp/metallb-webhook-backup.yaml
    fi
  fi
fi

# --- Summary ---
log "======================================"
log "Base K8s manifests applied"
log "======================================"
kubectl get namespaces
if [[ "${INSTALL_METALLB}" == "true" ]]; then
  echo ""
  log "MetalLB status:"
  kubectl get pods -n metallb-system
fi
