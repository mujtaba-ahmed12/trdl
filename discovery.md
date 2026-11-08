# TRDL Discovery

## Purpose and scope

Design and deploy a proof of concept (PoC) for The Responding Dark Laughter (TRDL), a web service where `GET /` returns `42`. The PoC runs on public cloud infrastructure with a container orchestrator and explores how the service could meet a high-availability requirement. It is not a production deployment or proof of a production SLA.


## Requirements and assumptions

| Item | Discovery |
| --- | --- |
| Required behavior | An HTTP `GET /` returns `42`. CRUD operations, a data platform, and authentication are not required by the exercise. |
| Availability | Several nines are requested, but the exact target and measurement window need stakeholder agreement. |
| Traffic and latency | Assumptions 250 requests/second, P95 under 50 ms, and P99 under 100 ms. Treat these as unvalidated assumptions, not demonstrated results. Define where latency is measured. |
| Security | Authentication and authorization are out of scope for the PoC. Protect the public endpoint and deployment credentials. |
| Environment | Use a dedicated Google Cloud project with billing enabled. Deployment scripts may assume Linux. |
| State | The response is constant; no database or persistent application state is needed. |

Define an SLI, measurement window, failure criteria, and a realistic target before making an SLA commitment.

## Proposed architecture and decisions

These are design choices, not claims that the infrastructure has already been deployed. The current request path is Cloudflare -> Google Cloud load balancer -> Kubernetes Service -> TRDL pods in regional GKE.

| Decision | Reasoning and tradeoffs |
| --- | --- |
| Google Cloud and regional GKE | Managed Kubernetes meets the orchestrator requirement and can distribute nodes across zones. A single regional cluster simplifies the PoC but does not protect against a region-wide outage. For production system we can use different such as multiregional deployments. |
| Google Cloud load balancer and Kubernetes Service | Expose the service and route traffic to healthy backends. Configure and verify the load balancer health check and its integration with the Service. |
| Deployment with at least three replicas | Multiple replicas can tolerate individual pod failures. Spread replicas across zones and nodes where capacity allows; three replicas alone do not guarantee availability. |
| HPA and cluster autoscaler | Scale pods using a custom metric other than CPU or memory, such as requests per second per pod. Expose the selected metric through a Kubernetes custom or external metrics API and select its target after testing. The cluster autoscaler adds nodes when pods cannot be scheduled because of insufficient capacity, based on their resource requests; it does not directly scale nodes from traffic or observed load. Set the maximum replica count and node limits after testing; scaling is not instantaneous. |
| Pod Disruption Budget | Limit voluntary disruptions during operations such as node drains. A PDB does not prevent involuntary failures or guarantee that capacity remains available. |
| Cloudflare gateway and WAF | Provides bot detection and edge protection. The proposed limit is 10 requests/second per client IP; evaluate false positives for shared IPs and the impact on load testing. Cloudflare adds configuration, cost, and another dependency, so decide whether to include it in the PoC or defer it. |
| Cloud Armor origin restriction | Allow Cloudflare's published egress IP ranges and deny other application traffic. Maintain both IPv4 and IPv6 ranges and account for load-balancer health checks. Cloudflare ranges are shared; use origin authentication as well to restrict access to the intended Cloudflare configuration. |
| GitHub Actions OIDC | Workload Identity Federation avoids long-lived Google Cloud service account keys. Restrict trust to the intended repository and, where practical, trusted branches or environments. |

## Failure scenarios and validation

- **Pod or node failure:** readiness checks remove unhealthy pods from traffic; remaining replicas must have enough capacity until replacement pods become ready. Test by terminating a pod and checking responses during recovery.
- **Zone failure:** replicas and nodes must be distributed across zones, with sufficient surviving capacity. A PDB only addresses voluntary disruptions. Document the expected degraded behavior; a zone failure test may be deferred if it exceeds the PoC budget.
- **Regional failure:** a single regional cluster is unavailable. Multi-region deployment and tested failover are potential production improvements, not PoC guarantees.
- **Traffic spike:** the HPA reacts to the selected custom metric by requesting more pods. If those pods cannot be scheduled, the cluster autoscaler can add nodes; both steps take time and can be constrained by limits or quotas. Load-test baseline capacity, observe errors and scaling, and consider what happens when the metric is unavailable. A single client IP cannot reach 11 requests/second through the proposed 10 requests/second limit without a deliberate test exception or distributed clients.
- **Edge or origin configuration failure:** a bad WAF rule, stale Cloudflare IP range, or blocked health check can interrupt service. Verify allowed traffic, denied direct-origin traffic, and health checks; document rollback.
- **Deployment failure:** use readiness checks and a rolling update; verify the rollout and document how to roll back to the previous version.

## Developer contract

The application should:

- Return HTTP 200 with body `42` for `GET /`, and have defined behavior for unsupported methods and paths.
- Listen on a configurable port on `0.0.0.0` and run in a container without depending on local state.
- Provide health endpoints, or a suitable existing endpoint, for readiness and liveness checks. Define how the load balancer checks health.
- Handle termination signals and shut down gracefully so in-flight requests can complete during a rollout.
- Write logs to standard output and standard error. Keep application credentials and configuration outside the image.

The deployment must define resource requests and limits, health probes, replica placement, a disruption budget, and autoscaling settings. Values should be validated rather than assumed.

## Deployment and automation plan

See the [deployment and automation plan](deployment.md).

## Testing and operational evidence

- Add automated tests for the successful response and unsupported paths or methods; run them in CI before building an image.
- Add a deployment smoke test for the public endpoint, and test pod replacement and rolling updates without assuming zero dropped requests.
- Measure throughput, error rate, and latency under representative load; record test conditions and distinguish direct-origin tests from Cloudflare-path tests.
- Propose external availability checks, request/error/latency monitoring, and alerts for production. A short PoC provides evidence about selected failure scenarios, not a statistically proven SLA.
- Plan controlled application and cluster upgrades, rollback, and eventual multi-region failover as production follow-ups.


## Open decisions

- What availability target, measurement window, and failure criteria do stakeholders require?
- Are the proposed throughput and latency targets required, and from which client locations and network path are they measured?
- Is Cloudflare required for the PoC, and how should its rate limit and origin authentication be tested?
- Which custom HPA metric and target, metrics provider, replica maximum, resource sizing, node limits, and zone placement are appropriate after testing?
- Which region, infrastructure tool, deployment permissions, and cost limits should be used?
- Which failure and upgrade tests fit the PoC budget, and which belong on the production roadmap?