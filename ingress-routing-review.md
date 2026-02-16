# Multi-Cluster Ingress Routing Configuration Review

## Executive Summary

This review assesses whether the Google Cloud Multi-Cluster Ingress (MCI) load balancer can successfully route traffic to pods across the configured clusters. The analysis reveals several configuration gaps that may prevent proper traffic routing.

## Configuration Overview

### MultiClusterIngress (hipster-mci)
**Location:** gcp-csm-mcp.sh:2052-2060, 2139-2160

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterIngress
metadata:
  name: hipster-mci
spec:
  template:
    spec:
      backend:
        serviceName: hipster-mcs
        servicePort: 80
```

### MultiClusterService (hipster-mcs)
**Location:** gcp-csm-mcp.sh:2100-2135

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterService
metadata:
  name: hipster-mcs
spec:
  template:
    spec:
      selector:
        app: frontend
      ports:
      - name: http
        protocol: TCP
        port: 80
        targetPort: 8080
  clusters:
  - link: "$CONFIG_ZONE/$CONFIG_CLUSTER"
  - link: "$REMOTE_ZONE/$REMOTE_CLUSTER"
```

### Frontend Deployment
**Location:** gcp-csm-mcp.sh:989-1019

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: server
        image: gcr.io/google-samples/microservices-demo/frontend:v0.3.9
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: "/_healthz"
            port: 8080
        livenessProbe:
          httpGet:
            path: "/_healthz"
            port: 8080
```

### Frontend Service
**Location:** gcp-csm-mcp.sh:1407-1415

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
```

## Analysis Findings

### ✅ Correct Configurations

1. **Label Matching**: The MultiClusterService selector (`app: frontend`) correctly matches the Frontend Deployment labels
2. **Port Mapping**: The port chain is correctly configured:
   - MCI → MCS: port 80
   - MCS → Service: port 80 → targetPort 8080
   - Service → Pod: targetPort 8080 → containerPort 8080
3. **Multi-Cluster Setup**: Both clusters are properly referenced in the MCS clusters list
4. **Pod Health Probes**: The frontend pods have readiness and liveness probes configured on `/_healthz`

### ⚠️ Critical Issues

#### 1. Missing BackendConfig for Health Checks
**Severity: HIGH**

The Google Cloud Load Balancer (GCLB) created by MCI needs explicit health check configuration. Without a BackendConfig, the load balancer may use default health checks that don't match the pod's `/_healthz` endpoint.

**Current State:**
- No BackendConfig resource defined
- MCI relies on default GCP health checks (likely HTTP GET on `/`)
- Pod health checks use `/_healthz` path

**Impact:**
- Backend pods may be marked as unhealthy by the load balancer
- Traffic may not be routed to pods even if they are running
- Users will experience 502/503 errors

**Recommended Fix:**
```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: frontend-backendconfig
  namespace: default
spec:
  healthCheck:
    checkIntervalSec: 10
    port: 8080
    type: HTTP
    requestPath: /_healthz
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  annotations:
    cloud.google.com/backend-config: '{"default": "frontend-backendconfig"}'
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
```

#### 2. Missing NEG (Network Endpoint Group) Configuration
**Severity: MEDIUM**

For optimal performance and direct pod-level routing, the Service should specify NEG annotations. Without this, routing goes through kube-proxy which adds latency.

**Recommended Fix:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default": "frontend-backendconfig"}'
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
```

#### 3. No Explicit Timeout Configuration
**Severity: LOW**

The BackendConfig should also include timeout settings to prevent premature connection termination.

**Recommended Addition to BackendConfig:**
```yaml
spec:
  timeoutSec: 30
  connectionDraining:
    drainingTimeoutSec: 60
```

### 🔍 Additional Observations

1. **IAM Permissions**: The script properly configures IAM permissions for the Multi-Cluster Ingress service account (gcp-csm-mcp.sh:554-555)

2. **Firewall Rules**: Appropriate firewall rules are configured for cross-cluster communication (gcp-csm-mcp.sh:662-663)

3. **Service Mesh Integration**: The deployment includes Istio service mesh with its own Gateway and VirtualService configuration, which may conflict with or duplicate the MCI routing

## Traffic Flow Analysis

### Current Flow (Potentially Broken)
```
Internet → GCP Load Balancer (MCI) → [Health Check Failure?] → No Traffic to Pods
```

### Expected Flow (After Fixes)
```
Internet
  → GCP Load Balancer (MCI)
  → Health Check (/_healthz via BackendConfig)
  → Network Endpoint Group (NEG)
  → Frontend Pods (port 8080)
```

## Recommendations

### Immediate Actions Required

1. **Add BackendConfig Resource** (Priority: HIGH)
   - Create BackendConfig with health check pointing to `/_healthz:8080`
   - Annotate frontend Service to reference this BackendConfig

2. **Enable NEG** (Priority: MEDIUM)
   - Add `cloud.google.com/neg: '{"ingress": true}'` annotation to frontend Service
   - This enables direct pod-level routing

3. **Configure Timeouts** (Priority: LOW)
   - Add timeout and connection draining settings to BackendConfig

### Testing Recommendations

After implementing the fixes:

1. **Verify MCI Status**
   ```bash
   kubectl describe MultiClusterIngress hipster-mci -n default
   ```
   - Check for `VIP` field (load balancer IP)
   - Verify status shows healthy backends

2. **Check Backend Health**
   ```bash
   gcloud compute backend-services list --filter="name~mci"
   gcloud compute backend-services get-health <backend-service-name> --global
   ```

3. **Test Traffic**
   ```bash
   curl -v http://<MCI_VIP>
   ```

4. **Monitor NEG Status**
   ```bash
   kubectl get svc frontend -n default -o yaml | grep neg
   gcloud compute network-endpoint-groups list
   ```

### Long-term Considerations

1. **Service Mesh vs MCI**: Consider whether you need both Istio Gateway and MCI, or if one should be primary
2. **Certificate Management**: For production, add SSL/TLS configuration to the MCI
3. **Session Affinity**: Consider if session affinity is needed for the frontend service
4. **CDN Integration**: Enable Cloud CDN for static content delivery

## Conclusion

**Can the load balancer route traffic to pods?**

**Current State: NO** - The configuration has critical gaps that will likely prevent successful traffic routing:
- Missing health check configuration means the load balancer cannot determine if pods are healthy
- Without proper health checks, backends will be marked unhealthy and receive no traffic

**After Implementing Fixes: YES** - With the recommended BackendConfig and NEG configuration, the load balancer will:
- Properly health check pods using the `/_healthz` endpoint
- Route traffic directly to healthy pod endpoints
- Maintain high availability across both clusters

## Next Steps

1. Implement the BackendConfig with health check configuration
2. Add NEG annotation to the frontend Service
3. Apply changes to the cluster
4. Wait 5-10 minutes for load balancer backend health checks to stabilize
5. Verify routing with curl tests and monitoring

---
**Review Date**: 2026-02-16
**Reviewed By**: Claude Code Assistant
**Configuration Source**: gcp-csm-mcp.sh
