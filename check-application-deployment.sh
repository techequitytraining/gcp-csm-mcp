#!/bin/bash

# Application Deployment Detection Script
# This script detects which application is deployed and validates namespace configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Application Deployment Detection"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl is not installed${NC}"
    exit 1
fi

# Function to print section headers
print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# 1. Check for Hipster Shop in default namespace
print_header "1. Checking for Hipster Shop (default namespace)"
HIPSTER_FOUND=false

if kubectl get service frontend -n default &> /dev/null; then
    echo -e "${GREEN}✓ Frontend service found in default namespace${NC}"
    HIPSTER_FOUND=true

    echo ""
    echo "Service details:"
    kubectl get service frontend -n default -o wide

    # Check for frontend deployment
    echo ""
    if kubectl get deployment frontend -n default &> /dev/null; then
        echo -e "${GREEN}✓ Frontend deployment found${NC}"
        FRONTEND_PODS=$(kubectl get pods -n default -l app=frontend --no-headers 2>/dev/null | wc -l)
        echo "  Pods: $FRONTEND_PODS"
    else
        echo -e "${YELLOW}⚠ Frontend deployment not found${NC}"
    fi

    # Check for other hipster shop services
    echo ""
    echo "Other Hipster Shop services in default namespace:"
    kubectl get services -n default | grep -E "emailservice|checkoutservice|recommendationservice|paymentservice|productcatalogservice|cartservice|currencyservice|shippingservice|adservice" || echo "  None found"
else
    echo -e "${YELLOW}✗ Frontend service NOT found in default namespace${NC}"
fi

# 2. Check for Bank of Anthos
print_header "2. Checking for Bank of Anthos (bank-of-anthos namespace)"
BANK_FOUND=false

if kubectl get namespace bank-of-anthos &> /dev/null; then
    echo -e "${GREEN}✓ bank-of-anthos namespace exists${NC}"

    # Check for services in bank-of-anthos namespace
    echo ""
    echo "Services in bank-of-anthos namespace:"
    SERVICE_COUNT=$(kubectl get services -n bank-of-anthos --no-headers 2>/dev/null | wc -l)

    if [ "$SERVICE_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $SERVICE_COUNT service(s)${NC}"
        kubectl get services -n bank-of-anthos
        BANK_FOUND=true

        # Check for deployments
        echo ""
        DEPLOYMENT_COUNT=$(kubectl get deployments -n bank-of-anthos --no-headers 2>/dev/null | wc -l)
        echo -e "Deployments: $DEPLOYMENT_COUNT"

        # Check for pods
        POD_COUNT=$(kubectl get pods -n bank-of-anthos --no-headers 2>/dev/null | wc -l)
        echo -e "Pods: $POD_COUNT"
    else
        echo -e "${YELLOW}✗ No services found in bank-of-anthos namespace${NC}"
    fi
else
    echo -e "${YELLOW}✗ bank-of-anthos namespace NOT found${NC}"
fi

# 3. Check for MCI/MCS
print_header "3. Checking Multi-Cluster Ingress Configuration"

# Check for MultiClusterService
echo "Checking for MultiClusterService..."
MCS_FOUND=false
MCS_NAMESPACE=""

if kubectl get multiclusterservice --all-namespaces &> /dev/null 2>&1; then
    MCS_LIST=$(kubectl get multiclusterservice --all-namespaces --no-headers 2>/dev/null | awk '{print $1":"$2}')
    if [ -n "$MCS_LIST" ]; then
        echo -e "${GREEN}✓ MultiClusterService found:${NC}"
        for mcs in $MCS_LIST; do
            MCS_NAMESPACE=$(echo $mcs | cut -d: -f1)
            MCS_NAME=$(echo $mcs | cut -d: -f2)
            echo "  - $MCS_NAME in namespace: $MCS_NAMESPACE"
            MCS_FOUND=true
        done
    else
        echo -e "${YELLOW}✗ No MultiClusterService found${NC}"
    fi
else
    echo -e "${YELLOW}✗ MultiClusterService CRD not available or no resources found${NC}"
fi

# Check for MultiClusterIngress
echo ""
echo "Checking for MultiClusterIngress..."
MCI_FOUND=false
MCI_NAMESPACE=""

if kubectl get multiclusteringress --all-namespaces &> /dev/null 2>&1; then
    MCI_LIST=$(kubectl get multiclusteringress --all-namespaces --no-headers 2>/dev/null | awk '{print $1":"$2}')
    if [ -n "$MCI_LIST" ]; then
        echo -e "${GREEN}✓ MultiClusterIngress found:${NC}"
        for mci in $MCI_LIST; do
            MCI_NAMESPACE=$(echo $mci | cut -d: -f1)
            MCI_NAME=$(echo $mci | cut -d: -f2)
            echo "  - $MCI_NAME in namespace: $MCI_NAMESPACE"
            MCI_FOUND=true

            # Get VIP if available
            VIP=$(kubectl get multiclusteringress $MCI_NAME -n $MCI_NAMESPACE -o jsonpath='{.status.VIP}' 2>/dev/null || echo "")
            if [ -n "$VIP" ]; then
                echo "    VIP: $VIP"
            else
                echo "    VIP: Not yet assigned"
            fi
        done
    else
        echo -e "${YELLOW}✗ No MultiClusterIngress found${NC}"
    fi
else
    echo -e "${YELLOW}✗ MultiClusterIngress CRD not available or no resources found${NC}"
fi

# 4. Analysis and Recommendations
print_header "4. Analysis & Recommendations"

# Determine deployment scenario
SCENARIO=""

if [ "$HIPSTER_FOUND" = true ] && [ "$BANK_FOUND" = false ]; then
    SCENARIO="hipster-only"
    echo -e "${BLUE}Detected Deployment: Hipster Shop (Step 7B)${NC}"
    echo "Application Namespace: default"
    echo ""

    if [ "$MCS_FOUND" = true ] && [ "$MCI_FOUND" = true ]; then
        # Check namespace alignment
        if [ "$MCS_NAMESPACE" = "default" ] && [ "$MCI_NAMESPACE" = "default" ]; then
            echo -e "${GREEN}✅ CONFIGURATION STATUS: CORRECT${NC}"
            echo ""
            echo "Namespace Alignment:"
            echo "  - Application (Hipster Shop): default ✓"
            echo "  - MultiClusterService: default ✓"
            echo "  - MultiClusterIngress: default ✓"
            echo ""
            echo -e "${GREEN}The namespace configuration is correct!${NC}"
            echo ""
            echo "Next Steps:"
            echo "  1. Apply BackendConfig and NEG fixes:"
            echo "     kubectl apply -f recommended-fixes.yaml"
            echo ""
            echo "  2. Wait 5-10 minutes for load balancer provisioning"
            echo ""
            echo "  3. Run verification:"
            echo "     ./verify-ingress-routing.sh"
        else
            echo -e "${RED}❌ CONFIGURATION STATUS: NAMESPACE MISMATCH${NC}"
            echo ""
            echo "Namespace Alignment:"
            echo "  - Application (Hipster Shop): default"
            echo "  - MultiClusterService: $MCS_NAMESPACE"
            echo "  - MultiClusterIngress: $MCI_NAMESPACE"
            echo ""
            echo -e "${RED}ERROR: MCI/MCS must be in 'default' namespace!${NC}"
            echo ""
            echo "Fix: Delete and recreate MCI/MCS in default namespace"
        fi
    else
        echo -e "${YELLOW}⚠ MCI/MCS not configured yet${NC}"
        echo ""
        echo "Next Steps:"
        echo "  1. Run Step 8 from the script to configure MCI/MCS"
        echo "  2. MCI/MCS will be created in default namespace (correct)"
        echo "  3. Apply BackendConfig fixes: kubectl apply -f recommended-fixes.yaml"
    fi

elif [ "$HIPSTER_FOUND" = false ] && [ "$BANK_FOUND" = true ]; then
    SCENARIO="bank-only"
    echo -e "${BLUE}Detected Deployment: Bank of Anthos (Step 7)${NC}"
    echo "Application Namespace: bank-of-anthos"
    echo ""

    if [ "$MCS_FOUND" = true ] && [ "$MCI_FOUND" = true ]; then
        # Check namespace alignment
        if [ "$MCS_NAMESPACE" = "bank-of-anthos" ] && [ "$MCI_NAMESPACE" = "bank-of-anthos" ]; then
            echo -e "${GREEN}✅ CONFIGURATION STATUS: CORRECT${NC}"
            echo ""
            echo "Namespace Alignment:"
            echo "  - Application (Bank of Anthos): bank-of-anthos ✓"
            echo "  - MultiClusterService: bank-of-anthos ✓"
            echo "  - MultiClusterIngress: bank-of-anthos ✓"
        elif [ "$MCS_NAMESPACE" = "default" ] || [ "$MCI_NAMESPACE" = "default" ]; then
            echo -e "${RED}❌ CONFIGURATION STATUS: CRITICAL NAMESPACE MISMATCH${NC}"
            echo ""
            echo "Namespace Alignment:"
            echo "  - Application (Bank of Anthos): bank-of-anthos"
            echo "  - MultiClusterService: $MCS_NAMESPACE ✗"
            echo "  - MultiClusterIngress: $MCI_NAMESPACE ✗"
            echo ""
            echo -e "${RED}CRITICAL ERROR:${NC} The existing MCI/MCS configuration is for Hipster Shop"
            echo "in the 'default' namespace. It CANNOT discover Bank of Anthos services"
            echo "in the 'bank-of-anthos' namespace."
            echo ""
            echo -e "${RED}This configuration will COMPLETELY FAIL to route traffic!${NC}"
            echo ""
            echo "Required Actions:"
            echo "  1. Delete existing MCI/MCS (they are misconfigured):"
            echo "     kubectl delete multiclusteringress hipster-mci -n default"
            echo "     kubectl delete multiclusterservice hipster-mcs -n default"
            echo ""
            echo "  2. Create new MCI/MCS configuration for Bank of Anthos"
            echo "     (requires knowledge of Bank of Anthos service labels and ports)"
            echo ""
            echo "  OR"
            echo ""
            echo "  3. Switch to Hipster Shop deployment:"
            echo "     - Delete Bank of Anthos: kubectl delete namespace bank-of-anthos"
            echo "     - Run Step 7B (Hipster Shop) from the script"
            echo "     - Run Step 8 (MCI/MCS will work)"
            echo ""
            echo "See: CRITICAL-namespace-mismatch.md for detailed analysis"
        fi
    else
        echo -e "${RED}❌ CONFIGURATION STATUS: INCOMPATIBLE${NC}"
        echo ""
        echo -e "${RED}WARNING:${NC} Step 8 (Configure MCI) in the script is hardcoded for Hipster Shop"
        echo "and will create MCI/MCS in the 'default' namespace."
        echo ""
        echo "This will NOT work with Bank of Anthos in 'bank-of-anthos' namespace!"
        echo ""
        echo "Options:"
        echo "  1. Switch to Hipster Shop (recommended for MCI demo):"
        echo "     - kubectl delete namespace bank-of-anthos"
        echo "     - Run Step 7B from script"
        echo "     - Run Step 8 from script"
        echo ""
        echo "  2. Manually create MCI/MCS for Bank of Anthos:"
        echo "     - DO NOT run Step 8"
        echo "     - Manually create MCI/MCS in bank-of-anthos namespace"
        echo "     - See CRITICAL-namespace-mismatch.md for details"
    fi

elif [ "$HIPSTER_FOUND" = true ] && [ "$BANK_FOUND" = true ]; then
    SCENARIO="both"
    echo -e "${YELLOW}Detected Deployment: BOTH Applications${NC}"
    echo "  - Hipster Shop in: default"
    echo "  - Bank of Anthos in: bank-of-anthos"
    echo ""
    echo -e "${YELLOW}⚠ Multiple applications detected${NC}"
    echo ""
    echo "MCI/MCS should target ONE application."
    echo "Determine which application you want to expose via MCI."

else
    SCENARIO="none"
    echo -e "${RED}No applications detected${NC}"
    echo ""
    echo "Neither Hipster Shop nor Bank of Anthos appears to be deployed."
    echo ""
    echo "Next Steps:"
    echo "  1. Run Step 7B to deploy Hipster Shop (recommended for MCI)"
    echo "  2. Then run Step 8 to configure MCI/MCS"
fi

# Summary
print_header "Summary"
echo "Deployment Scenario: $SCENARIO"
echo ""
echo "Resources Found:"
echo "  - Hipster Shop (default): $([ "$HIPSTER_FOUND" = true ] && echo '✓' || echo '✗')"
echo "  - Bank of Anthos (bank-of-anthos): $([ "$BANK_FOUND" = true ] && echo '✓' || echo '✗')"
echo "  - MultiClusterService: $([ "$MCS_FOUND" = true ] && echo "✓ ($MCS_NAMESPACE)" || echo '✗')"
echo "  - MultiClusterIngress: $([ "$MCI_FOUND" = true ] && echo "✓ ($MCI_NAMESPACE)" || echo '✗')"
echo ""

if [ "$SCENARIO" = "hipster-only" ] && [ "$MCS_NAMESPACE" = "default" ]; then
    echo -e "${GREEN}Configuration Status: Ready for MCI setup${NC}"
    echo "Review: ingress-routing-review.md (valid for this configuration)"
    echo "Fixes: recommended-fixes.yaml (apply these)"
elif [ "$SCENARIO" = "bank-only" ]; then
    echo -e "${RED}Configuration Status: Incompatible with script's Step 8${NC}"
    echo "Review: CRITICAL-namespace-mismatch.md (critical issue documented)"
else
    echo -e "${YELLOW}Configuration Status: Needs attention${NC}"
    echo "Review: CRITICAL-namespace-mismatch.md"
fi

echo ""
