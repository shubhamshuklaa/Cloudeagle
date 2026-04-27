# CloudEagle - DevOps Assignment Design Document

## Service context

`sync-service` is a Spring Boot backend service that:
- connects to MongoDB
- runs on GCP VMs
- has three environments: `qa`, `staging`, and `prod`
- is built and deployed through Jenkins

The goal of this design is to create a delivery model that is safe, easy to operate, cost-aware, and realistic for a growing startup team.

---

# Part 1 - Deployment & CI/CD Design

## 1. Branching strategy

### Proposed branches

- `feature/*` or `bugfix/*` - developer work branches
- `develop` - integration branch for QA
- `release/*` - release hardening branch for staging
- `main` - production-ready branch
- `vX.Y.Z` tags - production release trigger

### Branch to environment mapping

| Git ref | Purpose | Environment | Deployment behavior |
|---|---|---:|---|
| `feature/*` | developer work | none | PR validation only, never deploy |
| `develop` | integration testing | QA | auto deploy after merge |
| `release/*` | release validation | staging | auto deploy after merge |
| `main` | stable code line | none by default | build only or release prep |
| `vX.Y.Z` tag on `main` | official release | production | manual approval + deploy |

### Why this mapping is good

This keeps the release path simple:
- developers merge work into `develop`
- QA validates the integrated build
- a `release/*` branch is created when the team is preparing a release
- staging validates the release candidate
- production is deployed only from a version tag, not from a normal branch merge

This gives better control, easier rollback, and cleaner audit history.

### How accidental production deployments are prevented

Production safety should not depend on a single control. The right approach is to use multiple checks together:

1. **Protected `main` branch**
   - no direct push
   - merge only through PR
   - approvals required
   - mandatory status checks

2. **Protected release tags**
   - only release managers or CI bot can create `v*` tags

3. **Jenkins production rule**
   - production stage runs only when the build is triggered from a valid tag like `v1.4.0`

4. **Manual production approval**
   - Jenkins pauses before production deployment and waits for approval from approved users only

5. **Separate production credentials**
   - non-production jobs should not have permission to deploy into production

This is much safer than using “merge to main = deploy to prod”.

---

## 2. Jenkins pipeline design

### Pipeline style

Use a **Jenkins Multibranch Pipeline**. This is the best fit because it understands normal branches, pull requests, and tags.

### High-level stages

1. Checkout source code
2. Detect branch, PR, or release tag
3. Build with Maven
4. Run unit tests
5. Run code quality checks
6. Run integration tests
7. Build Docker image
8. Push image to Artifact Registry
9. Create or update VM startup configuration / instance template
10. Deploy to target Managed Instance Group
11. Run smoke tests
12. Roll back automatically if health checks fail

### PR vs merge behavior

#### On pull request
PR builds should be fast and safe.

What happens:
- checkout PR code
- compile the application
- run unit tests
- run quality checks
- optionally build image for validation
- publish build result back to source control
- **no deployment happens**

#### On merge to `develop`
What happens:
- build and test
- build Docker image
- push image to Artifact Registry
- deploy to QA
- run smoke test

#### On merge to `release/*`
What happens:
- build and test
- build Docker image
- push image to Artifact Registry
- deploy to staging
- run smoke test and release validation

#### On release tag from `main`
What happens:
- build and test
- build Docker image
- push image to Artifact Registry
- wait for manual approval
- deploy to production
- run smoke test
- mark release as successful

### Recommended artifact approach

Use **build once, deploy many**.

That means:
- build one immutable Docker image or one immutable release artifact
- push that exact version once
- deploy the same version to QA, staging, and production
- only configuration and secrets change per environment

This reduces drift between environments.

### Rollback strategy if deployment fails

For GCP VMs, the cleanest rollback model is **instance template rollback**.

Recommended process:
1. record the current Managed Instance Group template before deployment
2. create a new instance template using the new app version
3. start a rolling update
4. wait for new VMs to become healthy
5. run smoke tests
6. if health check or smoke test fails, update the MIG back to the previous template

This gives a practical and fast rollback path.

### Database rollback rule

Application rollback is easy only when database changes are safe.

For MongoDB changes:
- use backward-compatible changes first
- avoid destructive schema changes in the same release
- use an expand -> migrate -> contract pattern
- take backup or snapshot before risky production changes

---

## 3. Configuration management

### Managing environment-specific configuration

Keep configuration outside the application image.

Recommended pattern:
- common defaults inside the application
- environment-specific overrides using Spring profiles
- runtime environment selected using `SPRING_PROFILES_ACTIVE`

Example profile files:
- `application-qa.yml`
- `application-staging.yml`
- `application-prod.yml`

### What should be treated as non-secret config

Examples:
- log levels
- service URLs
- connection pool values
- feature flags
- timeouts
- environment-specific tuning values

### Secrets handling

Secrets must never live in:
- Git repository
- Jenkinsfile
- Docker image
- VM template metadata in plain text

Recommended approach:
- store MongoDB URI, username/password, API keys, and service secrets in **Google Secret Manager**
- use one runtime service account per environment
- give each service account access only to that environment’s secrets
- load secrets at startup using Secret Manager or a startup script

### Jenkins secret handling

Jenkins should keep only deployment-related secrets such as:
- SCM credentials
- short-lived cloud auth or federated identity setup
- notification credentials
- registry auth if required

Avoid storing long-lived service account key files if possible.

---

## 4. Deployment strategy

### Option comparison

| Strategy | Strength | Weakness | Decision |
|---|---|---|---|
| Recreate | simple | causes downtime | reject |
| Blue/Green | safest cutover and easy rollback | needs duplicate capacity and higher cost | useful for rare high-risk releases |
| Rolling | lower cost, simple, works well with GCP MIG | rollback is not as instant as blue/green | recommended |

### Recommended choice

Use **Rolling deployment** as the default strategy.

Why:
- matches GCP VM deployment model very well
- works naturally with Managed Instance Groups
- supports minimal downtime
- lower cost than Blue/Green
- easier for a startup team to operate

### Minimal downtime approach

To achieve minimal downtime:
- use a **regional Managed Instance Group**
- put an **HTTP(S) load balancer** in front of the service
- use health checks against `/actuator/health`
- use rolling update settings such as `maxUnavailable=0` and small `maxSurge`
- enable graceful shutdown in Spring Boot
- make sure the app becomes ready only after dependencies are reachable

### Production deployment flow

1. Jenkins builds a new version
2. new image is pushed to Artifact Registry
3. new instance template is created
4. MIG starts rolling update
5. new VMs pass health checks
6. load balancer sends traffic only to healthy instances
7. if checks fail, rollback to previous template

---

# Part 2 - Infrastructure Design

## 5. Compute choice

### Recommended option: Compute Engine Managed Instance Group

Because the assignment already says the service runs on GCP VMs, the strongest answer is:

**Compute Engine + regional Managed Instance Group + Load Balancer**

### Why not GKE

GKE is powerful, but for a single Spring Boot service it adds more platform complexity than needed:
- cluster management overhead
- Kubernetes learning curve
- more moving parts than this assignment needs

### Why not Cloud Run as the main answer

Cloud Run is a strong future option, but for this assignment it changes the operating model from VMs to serverless containers. Since the service is already said to run on VMs, Compute Engine is the cleaner answer.

### Why Compute Engine MIG is the best fit

It provides:
- autoscaling
- autohealing
- rolling updates
- easy integration with load balancer
- direct fit for VM-based runtime
- lower complexity than GKE

---

## 6. MongoDB hosting approach

### Recommended choice: MongoDB Atlas on GCP

Recommended because it gives:
- managed backups
- point-in-time recovery
- easier high availability
- private connectivity options
- lower operational burden

### Why not self-managed MongoDB on VMs

Self-managing MongoDB means the team must handle:
- patching
- backup and restore
- failover design
- monitoring
- replica set operations
- network hardening

That is usually not worth it for a startup unless there is a very specific business reason.

---

## 7. Networking basics

### Recommended network design

- separate project per environment if possible
- private VPC subnets
- application VMs should stay private
- use internal load balancer by default for internal service use
- if internet access is needed, place service behind external HTTPS load balancer while keeping VMs private

### Security controls

- strict firewall rules
- no public SSH access to VMs
- admin access through **IAP TCP forwarding**
- use **Cloud NAT** for outbound internet access from private VMs
- use **Private Google Access** for Google APIs from private VMs
- use **Cloud Armor** if service is internet-facing

### Database connectivity

If using Atlas, use private connectivity such as private endpoint / PSC so database traffic does not go over the public internet.

---

## 8. Secrets and IAM

### IAM model

Keep IAM simple and strict:
- one runtime service account per environment
- one separate deployment service account for Jenkins
- no broad roles like `Editor` in production
- use least privilege roles only

### Secret handling

- secrets stored in Secret Manager
- runtime service account reads only its own environment secrets
- production secrets separated from non-production secrets
- secret access is audited

This improves security and reduces blast radius.

---

## 9. Logging and monitoring stack

### Recommended observability stack

Use native GCP services:
- **Cloud Logging**
- **Cloud Monitoring**
- **Ops Agent** on VMs
- optional **Cloud Trace** for request tracing

### What to monitor

At minimum:
- VM health
- CPU and memory
- application error rate
- response latency
- 5xx responses
- deployment failures
- rollback events
- MongoDB connection failures

### Alert examples

Create alerts for:
- unhealthy backend instances
- high error rate
- JVM memory pressure
- high latency
- failed deployment
- repeated autohealing events

---

## 10. Cost-aware starting setup

A practical starting point:

| Environment | VM type | Min instances | Max instances | Notes |
|---|---:|---:|---:|---|
| QA | e2-standard-2 | 1 | 2 | low cost, enough for testing |
| Staging | e2-standard-2 | 1 | 3 | near-prod validation |
| Production | e2-standard-4 | 2 | 6 | safer capacity and zone resilience |

This should be adjusted after load testing and production telemetry.

### Cost optimization ideas

- use autoscaling instead of fixed oversized capacity
- use regional MIG only for production if budget is tight
- use smaller non-prod instances
- use Spot VMs for non-critical supporting workloads like ephemeral Jenkins agents

---

## Final recommendation

The best overall answer for this assignment is:
- Jenkins Multibranch Pipeline
- `develop -> QA`, `release/* -> staging`, `vX.Y.Z tag -> production`
- production protected by branch rules, tag rules, and manual approval
- immutable image in Artifact Registry
- runtime on Compute Engine Managed Instance Groups
- rolling deployment with minimal downtime
- secrets in Secret Manager
- MongoDB Atlas on GCP
- logging and monitoring through Cloud Logging, Monitoring, and Ops Agent

This design is simple, production-friendly, secure, and realistic for a startup.
