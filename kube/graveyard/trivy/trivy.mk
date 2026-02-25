
# Before the first deploy you get a weird error from Helmfile/diff plugin because the CRDs dont exist yet:
# Error: Failed to render chart: exit status 1: Error: unable to build kubernetes objects from release manifest: unable to recognize "": no matches for kind "ClusterComplianceReport" in version "aquasecurity.github.io/v1alpha1"
.PHONY: trivy-deploy-first-time
trivy-deploy-first-time:
	helm repo add aqua https://aquasecurity.github.io/helm-charts/
	helm repo update
	helm install trivy-operator aqua/trivy-operator \
		--namespace trivy-system \
		--create-namespace

.PHONY: trivy-deploy
trivy-deploy:
	helmfile --file ./observation/trivy/helmfile.yaml apply

.PHONY: trivy-remove
trivy-remove:
	helmfile --file ./observation/trivy/helmfile.yaml destroy

.PHONY: trivy-reports
trivy-reports:
	@make -s trivy-config-audit-reports
	@make -s trivy-vuln-reports
	@make -s trivy-exposed-secrets-reports
	@make -s trivy-rbac-reports
	@make -s trivy-cluster-rbac-reports

	@echo "For more information see: https://aquasecurity.github.io/trivy-operator/v0.2.0/vulnerability-scanning/"
	@echo ""

.PHONY: trivy-vuln-reports
trivy-vuln-reports:
	@echo "======================================================================="
	@echo "= VulnerabilityReport - vulnerabilities found in a container image of ="
	@echo "=                       of a given Kubernetes workload                ="
	@echo "=   kubectl get vulnerabilityreports -A -o wide                       ="
	@echo "======================================================================="
	@kubectl get vulnerabilityreports -A -o wide
	@echo ""

.PHONY: trivy-config-audit-reports
trivy-config-audit-reports:
	@echo "======================================================================="
	@echo "= ConfigAuditReport - Kube object config scanning                     ="
	@echo "=   kubectl get configauditreports -A -o wide                         ="
	@echo "======================================================================="
	@kubectl get configauditreports -A -o wide
	@echo ""

.PHONY: trivy-exposed-secrets-reports
trivy-exposed-secrets-reports:
	@echo "======================================================================="
	@echo "= ExposedSecretReport - Secrets found in registry images              ="
	@echo "=   kubectl get exposedsecrets -A -o wide                             ="
	@echo "======================================================================="
	@kubectl get exposedsecrets -A -o wide
	@echo ""

.PHONY: trivy-rbac-reports
trivy-rbac-reports:
	@echo "======================================================================="
	@echo "= RbacAssessmentReport - Analysis of Namspaced scoped Kube RBAC       ="
	@echo "=   kubectl get rbacassessmentreports -A -o wide                      ="
	@echo "======================================================================="
	@kubectl get rbacassessmentreports -A -o wide
	@echo ""

.PHONY: trivy-cluster-rbac-reports
trivy-cluster-rbac-reports:
	@echo "======================================================================="
	@echo "= ClusterRbacAssessmentReport - Analysis of Cluster scoped Kube RBAC  ="
	@echo "=   kubectl get clusterrbacassessmentreports -A -o wide               ="
	@echo "======================================================================="
	@kubectl get clusterrbacassessmentreports -A -o wide
	@echo ""