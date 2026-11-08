.PHONY: bootstrap

export PROJECT_ID REPOSITORY

bootstrap:
	@set -eu; \
	if [ -z "$${PROJECT_ID:-}" ] || [ -z "$${REPOSITORY:-}" ]; then \
		printf '%s\n' 'Usage: make bootstrap PROJECT_ID=<project-id> REPOSITORY=<owner/repository>' >&2; \
		exit 1; \
	fi; \
	if ! printf '%s\n' "$$REPOSITORY" | grep -Eq '^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$$'; then \
		printf '%s\n' 'REPOSITORY must be in owner/repository format.' >&2; \
		exit 1; \
	fi; \
	command -v gcloud >/dev/null || { printf '%s\n' 'gcloud is required.' >&2; exit 1; }; \
	pool=trdl-github; \
	provider=github; \
	account=terraform_service_account; \
	service_account="$$account@$$PROJECT_ID.iam.gserviceaccount.com"; \
	gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com cloudresourcemanager.googleapis.com --project="$$PROJECT_ID"; \
	project_number=$$(gcloud projects describe "$$PROJECT_ID" --format='value(projectNumber)'); \
	if ! gcloud iam workload-identity-pools describe "$$pool" --location=global --project="$$PROJECT_ID" >/dev/null 2>&1; then \
		gcloud iam workload-identity-pools create "$$pool" --location=global --project="$$PROJECT_ID" --display-name='GitHub Actions'; \
	fi; \
	if gcloud iam workload-identity-pools providers describe "$$provider" --workload-identity-pool="$$pool" --location=global --project="$$PROJECT_ID" >/dev/null 2>&1; then \
		provider_action=update-oidc; \
	else \
		provider_action=create-oidc; \
	fi; \
	gcloud iam workload-identity-pools providers "$$provider_action" "$$provider" \
		--workload-identity-pool="$$pool" --location=global --project="$$PROJECT_ID" \
		--issuer-uri='https://token.actions.githubusercontent.com' \
		--attribute-mapping='google.subject=assertion.sub,attribute.repository=assertion.repository' \
		--attribute-condition="assertion.repository == '$$REPOSITORY'"; \
	if ! gcloud iam service-accounts describe "$$service_account" --project="$$PROJECT_ID" >/dev/null 2>&1; then \
		gcloud iam service-accounts create "$$account" --project="$$PROJECT_ID" --display-name='GitHub Actions'; \
	fi; \
	gcloud iam service-accounts add-iam-policy-binding "$$service_account" --project="$$PROJECT_ID" \
		--role=roles/iam.workloadIdentityUser \
		--member="principalSet://iam.googleapis.com/projects/$$project_number/locations/global/workloadIdentityPools/$$pool/attribute.repository/$$REPOSITORY"; \
	for role in roles/resourcemanager.projectIamAdmin roles/iam.serviceAccountAdmin; do \
		gcloud projects add-iam-policy-binding "$$PROJECT_ID" --member="serviceAccount:$$service_account" --role="$$role"; \
	done; \
	printf '\nWorkload identity provider: projects/%s/locations/global/workloadIdentityPools/%s/providers/%s\nService account: %s\n' \
		"$$project_number" "$$pool" "$$provider" "$$service_account"
