include observation/kube-prometheus-stack/prometheus.mk
include observation/kube-prometheus-stack/grafana.mk

.PHONY: kube-prometheus-stack-crds
kube-prometheus-stack-crds:
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagerconfigs.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_probes.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.56.0/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml

.PHONY: kube-prometheus-stack-deploy
kube-prometheus-stack-deploy:
	@echo "Make sure you have applied CRDs to your cluster first: "
	@echo "  make kube-prometheus-stack-crds\n"
	helmfile --file ./observation/kube-prometheus-stack/helmfile.yaml apply
	kubectl apply -f ./observation/kube-prometheus-stack/network.yml

.PHONY: kube-prometheus-stack-remove
kube-prometheus-stack-remove:
	kubectl delete -f ./observation/kube-prometheus-stack/network.yml
	helmfile --file ./observation/kube-prometheus-stack/helmfile.yaml destroy
