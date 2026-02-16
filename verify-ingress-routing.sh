#!/bin/bash

# Multi-Cluster Ingress Routing Verification Script
# This script helps verify that the MCI load balancer can route traffic to pods

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Multi-Cluster Ingress Routing Verification"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl is not installed${NC}"
    exit 1
fi

# Check if gcloud is available
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}ERROR: gcloud is not installed${NC}"
    exit 1
fi

# Function to print section headers
print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Function to check status
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        return 1
    fi
}

# 1. Check MultiClusterIngress exists
print_header "1. Checking MultiClusterIngress"
echo "Checking if hipster-mci exists..."
if kubectl get multiclusteringress hipster-mci -n default &> /dev/null; then
    echo -e "${GREEN}✓ MultiClusterIngress exists${NC}"
    echo ""
    echo "MCI Details:"
    kubectl describe multiclusteringress hipster-mci -n default | grep -A 5 "Status:"
else
    echo -e "${RED}✗ MultiClusterIngress not found${NC}"
    exit 1
fi

# 2. Check MultiClusterService exists
print_header "2. Checking MultiClusterService"
echo "Checking if hipster-mcs exists..."
if kubectl get multiclusterservice hipster-mcs -n default &> /dev/null; then
    echo -e "${GREEN}✓ MultiClusterService exists${NC}"
    echo ""
    echo "MCS Details:"
    kubectl get multiclusterservice hipster-mcs -n default -o yaml | grep -A 10 "spec:"
else
    echo -e "${RED}✗ MultiClusterService not found${NC}"
    exit 1
fi

# 3. Check Frontend Service configuration
print_header "3. Checking Frontend Service"
echo "Checking frontend service configuration..."
if kubectl get service frontend -n default &> /dev/null; then
    echo -e "${GREEN}✓ Frontend service exists${NC}"

    # Check for BackendConfig annotation
    echo ""
    echo "Checking for BackendConfig annotation..."
    BACKEND_CONFIG=$(kubectl get service frontend -n default -o jsonpath='{.metadata.annotations.cloud\.google\.com/backend-config}')
    if [ -n "$BACKEND_CONFIG" ]; then
        echo -e "${GREEN}✓ BackendConfig annotation found: $BACKEND_CONFIG${NC}"
    else
        echo -e "${YELLOW}⚠ BackendConfig annotation missing (health checks may fail)${NC}"
    fi

    # Check for NEG annotation
    echo ""
    echo "Checking for NEG annotation..."
    NEG_CONFIG=$(kubectl get service frontend -n default -o jsonpath='{.metadata.annotations.cloud\.google\.com/neg}')
    if [ -n "$NEG_CONFIG" ]; then
        echo -e "${GREEN}✓ NEG annotation found: $NEG_CONFIG${NC}"
    else
        echo -e "${YELLOW}⚠ NEG annotation missing (direct pod routing not enabled)${NC}"
    fi

    # Check port configuration
    echo ""
    echo "Checking port configuration..."
    SERVICE_PORT=$(kubectl get service frontend -n default -o jsonpath='{.spec.ports[0].port}')
    TARGET_PORT=$(kubectl get service frontend -n default -o jsonpath='{.spec.ports[0].targetPort}')
    echo "Service port: $SERVICE_PORT → Target port: $TARGET_PORT"
    if [ "$SERVICE_PORT" = "80" ] && [ "$TARGET_PORT" = "8080" ]; then
        echo -e "${GREEN}✓ Port configuration correct${NC}"
    else
        echo -e "${RED}✗ Port configuration incorrect${NC}"
    fi
else
    echo -e "${RED}✗ Frontend service not found${NC}"
    exit 1
fi

# 4. Check BackendConfig exists (if referenced)
if [ -n "$BACKEND_CONFIG" ]; then
    print_header "4. Checking BackendConfig"
    BACKEND_CONFIG_NAME=$(echo $BACKEND_CONFIG | jq -r '.default' 2>/dev/null || echo "")
    if [ -n "$BACKEND_CONFIG_NAME" ]; then
        echo "Checking BackendConfig: $BACKEND_CONFIG_NAME"
        if kubectl get backendconfig $BACKEND_CONFIG_NAME -n default &> /dev/null; then
            echo -e "${GREEN}✓ BackendConfig exists${NC}"
            echo ""
            echo "Health check configuration:"
            kubectl get backendconfig $BACKEND_CONFIG_NAME -n default -o yaml | grep -A 10 "healthCheck:"
        else
            echo -e "${RED}✗ BackendConfig not found${NC}"
        fi
    fi
fi

# 5. Check Frontend Pods
print_header "5. Checking Frontend Pods"
echo "Checking if frontend pods are running..."
POD_COUNT=$(kubectl get pods -n default -l app=frontend --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ $POD_COUNT frontend pod(s) running${NC}"
    echo ""
    echo "Pod status:"
    kubectl get pods -n default -l app=frontend -o wide

    # Check pod readiness
    echo ""
    echo "Checking pod readiness..."
    READY_PODS=$(kubectl get pods -n default -l app=frontend --no-headers 2>/dev/null | grep -c "1/1" || echo "0")
    if [ "$READY_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓ $READY_PODS pod(s) ready${NC}"
    else
        echo -e "${YELLOW}⚠ No pods are ready${NC}"
    fi
else
    echo -e "${RED}✗ No frontend pods running${NC}"
fi

# 6. Check GCP Load Balancer Backend Health (requires project info)
print_header "6. GCP Load Balancer Backend Health"
echo "Attempting to check GCP backend health..."

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${YELLOW}⚠ Cannot determine project ID. Skipping GCP health check.${NC}"
else
    echo "Project: $PROJECT_ID"

    # Try to find MCI-related backend services
    echo ""
    echo "Searching for MCI backend services..."
    BACKEND_SERVICES=$(gcloud compute backend-services list --filter="name~mci" --format="value(name)" 2>/dev/null || echo "")

    if [ -n "$BACKEND_SERVICES" ]; then
        for BS in $BACKEND_SERVICES; do
            echo ""
            echo "Backend Service: $BS"
            echo "Health Status:"
            gcloud compute backend-services get-health "$BS" --global 2>/dev/null || echo "Unable to retrieve health status"
        done
    else
        echo -e "${YELLOW}⚠ No MCI backend services found (may still be provisioning)${NC}"
        echo "   This is normal if the MCI was recently created."
        echo "   It can take 5-10 minutes for the load balancer to provision."
    fi
fi

# 7. Get MCI IP Address
print_header "7. MCI Load Balancer IP"
echo "Retrieving MCI VIP (Virtual IP)..."
MCI_VIP=$(kubectl get multiclusteringress hipster-mci -n default -o jsonpath='{.status.VIP}' 2>/dev/null || echo "")

if [ -n "$MCI_VIP" ]; then
    echo -e "${GREEN}✓ MCI VIP: $MCI_VIP${NC}"
    echo ""
    echo "Test the ingress with:"
    echo "  curl -v http://$MCI_VIP"
    echo "  curl -v http://$MCI_VIP/_healthz"
else
    echo -e "${YELLOW}⚠ MCI VIP not yet assigned${NC}"
    echo "   The load balancer is still provisioning."
    echo "   Check again in a few minutes with:"
    echo "   kubectl describe multiclusteringress hipster-mci -n default"
fi

# 8. Network Endpoint Groups
print_header "8. Network Endpoint Groups (NEGs)"
if [ -n "$NEG_CONFIG" ] && [ -n "$PROJECT_ID" ]; then
    echo "Checking for NEGs..."
    NEGS=$(gcloud compute network-endpoint-groups list --filter="name~frontend" --format="value(name,zone)" 2>/dev/null || echo "")

    if [ -n "$NEGS" ]; then
        echo -e "${GREEN}✓ NEGs found:${NC}"
        echo "$NEGS"
    else
        echo -e "${YELLOW}⚠ No NEGs found yet (may still be creating)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ NEG not configured or cannot check${NC}"
fi

# Summary
print_header "Summary"
echo "Configuration Review:"
echo ""
echo "Items to verify:"
echo "1. MultiClusterIngress exists: $(kubectl get mci hipster-mci -n default &>/dev/null && echo '✓' || echo '✗')"
echo "2. MultiClusterService exists: $(kubectl get mcs hipster-mcs -n default &>/dev/null && echo '✓' || echo '✗')"
echo "3. Frontend Service exists: $(kubectl get svc frontend -n default &>/dev/null && echo '✓' || echo '✗')"
echo "4. BackendConfig annotation: $([ -n \"$BACKEND_CONFIG\" ] && echo '✓' || echo '✗')"
echo "5. NEG annotation: $([ -n \"$NEG_CONFIG\" ] && echo '✓' || echo '✗')"
echo "6. Frontend pods running: $([ \"$POD_COUNT\" -gt 0 ] && echo '✓' || echo '✗')"
echo "7. MCI VIP assigned: $([ -n \"$MCI_VIP\" ] && echo '✓' || echo '✗')"
echo ""

if [ -z "$BACKEND_CONFIG" ]; then
    echo -e "${RED}CRITICAL:${NC} BackendConfig is missing!"
    echo "The load balancer cannot perform health checks correctly."
    echo "Apply the recommended fixes:"
    echo "  kubectl apply -f recommended-fixes.yaml"
    echo ""
fi

if [ -z "$MCI_VIP" ]; then
    echo -e "${YELLOW}NOTE:${NC} MCI is still provisioning. Wait 5-10 minutes and run this script again."
    echo ""
fi

echo "For detailed analysis, see: ingress-routing-review.md"
echo ""
