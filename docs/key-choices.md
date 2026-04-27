# Key Architecture Choices

This file gives a quick explanation of why the main design decisions were made.

## 1. Why Jenkins Multibranch Pipeline?

Because the assignment already says Jenkins is used.

Multibranch Pipeline is the cleanest way to handle:
- feature branches
- pull requests
- release branches
- main branch
- release tags

It also makes it easy to apply different behavior for PR validation, QA deployment, staging deployment, and production deployment.

## 2. Why deploy to QA from `develop`?

QA should receive the latest integrated code quickly so the team can catch issues early.

This gives fast feedback and helps avoid a big batch of problems later.

## 3. Why deploy to staging from `release/*`?

Staging should behave like a release candidate environment.

Using a dedicated `release/*` branch helps the team stabilize a release without blocking normal development on `develop`.

## 4. Why production only from tags?

Production should represent a clear, versioned release.

Tag-based production deployment gives:
- better traceability
- better rollback history
- cleaner release management
- less risk than deploying from a moving branch head

## 5. Why rolling deployment instead of blue/green?

Rolling deployment is the best balance for this assignment.

It gives:
- minimal downtime
- lower cost than blue/green
- natural fit with Managed Instance Groups
- simpler operations for a small DevOps team

Blue/green is still a good option for rare, very high-risk releases, but it is usually more expensive because it needs duplicate capacity.

## 6. Why Compute Engine Managed Instance Group instead of GKE?

The assignment already says the service is deployed to GCP VMs.

Using Compute Engine Managed Instance Groups keeps the answer aligned with that requirement and avoids adding Kubernetes complexity for a single service.

## 7. Why MongoDB Atlas instead of self-managed MongoDB?

Atlas removes a lot of operational work:
- backups
- failover
- maintenance
- recovery
- operational monitoring burden

That lets the team focus on the application instead of database operations.

## 8. Why keep VMs private?

Private VMs reduce attack surface.

The safer pattern is:
- keep application VMs private
- expose only the load balancer if needed
- use IAP for admin access
- use Cloud NAT for outbound access

## 9. Why Secret Manager?

It is the cleanest way to keep secrets out of:
- source code
- Docker images
- Jenkinsfile
- VM templates

It also supports least privilege access and auditability.

## 10. Why use Cloud Logging + Monitoring + Ops Agent?

Because it gives a strong native observability stack on GCP without adding unnecessary third-party tooling on day one.

It is enough for:
- logs
- metrics
- dashboards
- alerts
- VM monitoring
- deployment visibility

## Final thought

The overall design is built to be:
- simple
- safe
- practical
- cost-aware
- production-ready

That makes it a strong answer for an interview assignment and also a realistic starting point for a real project.
