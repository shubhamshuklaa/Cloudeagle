# CloudEagle - sync-service DevOps Assignment

This repository contains the deliverables for the CloudEagle DevOps assignment for a Spring Boot service named `sync-service`.

## What is included

### Part 1 - Deployment & CI/CD Design
- `docs/design.md` - short design document covering branching strategy, Jenkins pipeline flow, configuration handling, secrets handling, deployment strategy, rollback, and minimal downtime approach
- `Jenkinsfile` - Jenkins multibranch pipeline for PR validation, QA deployment, staging deployment, and production deployment with manual approval

### Part 2 - Infrastructure Design
- `diagram/architecture.png` - architecture diagram
- `docs/key-choices.md` - written explanation of the main infrastructure decisions

## Recommended repository structure

```text
.
├── README.md
├── Jenkinsfile
├── docs
│   ├── design.md
│   └── key-choices.md
├── diagram
│   ├── architecture.png
│   └── architecture.mmd
└── scripts
    ├── deploy_mig.sh
    └── rollback_mig.sh
```

## Design summary

The recommended solution keeps the service deployment model aligned with the assignment requirement of running on GCP VMs.

- `develop` branch deploys to **QA**
- `release/*` branches deploy to **staging**
- only version tags like `v1.0.0` from `main` can deploy to **production**
- production deployment uses **manual approval** and **protected branches/tags**
- runtime uses **Compute Engine Managed Instance Groups**, **Artifact Registry**, **Secret Manager**, **MongoDB Atlas**, **Cloud Logging**, and **Cloud Monitoring**

## How to use this repo

1. Upload all files in this folder to your GitHub repository.
2. Add your actual GCP project IDs, region, repository names, and MIG names in the `Jenkinsfile` and scripts.
3. Replace placeholder values such as service accounts, secret names, and health check URLs with your own values.
4. Commit and push.

## Notes

This is intentionally designed in a practical, interview-friendly way:
- simple to understand
- production-safe
- cost-conscious for a startup
- realistic for a small DevOps team
