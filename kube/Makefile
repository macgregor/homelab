KUBECONFIG?=${HOME}/.kube/homelab_config
node?=k3-m1
pod?=
n?=default
DEBUG_POD_NAME?=`kubectl -n kube-system get pods --field-selector spec.nodeName=${node} --no-headers -o name | grep network-multitool | head -n 1`

include sys/cert-manager/cert-manager.mk
include sys/democratic-csi/democratic-csi.mk
include sys/ingress-nginx/internal/ingress-nginx.mk
include sys/ingress-nginx/external/ingress-nginx.mk
include sys/metallb/metallb.mk
include sys/oauth2-proxy/oauth2-proxy.mk
include sys/loki/loki.mk
include sys/fluent-bit/fluent-bit.mk
include sys/kube-prometheus-stack/kube-prometheus-stack.mk
include app/network-multitool/network-multitool.mk
include app/foundry-vtt/foundry-vtt.mk
include app/jellyfin/jellyfin.mk
include app/synology-dsm/synology-dsm.mk
include app/arr/sonarr/sonarr.mk
include app/arr/radarr/radarr.mk
include app/arr/qbittorrent/qbittorrent.mk
include app/arr/prowlarr/prowlarr.mk
#include app/grafana/grafana.mk
include demo/whoami/whoami.mk
include demo/kuard/kuard.mk

.PHONY: pod-debug
pod-debug:
	kubectl -n ${n} exec -it ${pod} -- sh

.PHONY: cluster-debug
cluster-debug:
	kubectl -n kube-system exec -it ${DEBUG_POD_NAME} -- bash

.PHONY: ingress-logs
ingress-logs:
	kubectl -n ingress-nginx logs deployment/ingress-nginx-controller --follow

.PHONY: deploy-sys
deploy-sys: democratic-csi-deploy cert-manager-deploy metallb-deploy ingress-internal-deploy ingress-external-deploy oauth2-proxy-deploy loki-deploy fluent-bit-deploy kube-prometheus-stack-deploy
	@echo "Done."

.PHONY: remove-sys
remove-sys: democratic-csi-remove cert-manager-remove metallb-remove ingress-internal-remove ingress-external-remove oauth2-proxy-remove loki-remove fluent-bit-remove kube-prometheus-stack-remove
	@echo "Done."

.PHONY: deploy-apps
deploy-apps: foundry-vtt-deploy jellyfin-deploy network-multitool-deploy synology-dsm-deploy sonarr-deploy prowlarr-deploy radarr-deploy qbittorrent-deploy
	@echo "Done."

.PHONY: remove-apps
remove-apps: foundry-vtt-remove jellyfin-remove network-multitool-remove synology-dsm-remove sonarr-remove prowlarr-remove radarr-remove qbittorrent-remove
	@echo "Done."

.PHONY: deploy-demos
deploy-demos: whoami-deploy kuard-deploy
	@echo "Done."

.PHONY: remove-demos
remove-demos: whoami-remove kuard-remove
	@echo "Done."

.PHONY: deploy-all
deploy-all: deploy-sys deploy-apps deploy-demos
	@echo "Done."

.PHONY: remove-all
remove-all: remove-apps remove-sys remove-demos
	@echo "Done."
