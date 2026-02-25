KUBECONFIG?=${HOME}/.kube/homelab_config
node?=k3-m1
pod?=
n?=default
DEBUG_POD_NAME?=`kubectl -n kube-system get pods --field-selector spec.nodeName=${node} --no-headers -o name | grep network-multitool | head -n 1`

# Sys
include sys/coredns/coredns.mk
include sys/cert-manager/cert-manager.mk
include sys/democratic-csi/democratic-csi.mk
include sys/ingress-nginx/internal/ingress-nginx.mk
include sys/ingress-nginx/external/ingress-nginx.mk
include sys/metallb/metallb.mk
include sys/oauth2-proxy/oauth2-proxy.mk

# Observation
include observation/loki/loki.mk
include observation/fluent-bit/fluent-bit.mk
include observation/kube-prometheus-stack/kube-prometheus-stack.mk

# Media
include media/jellyfin/jellyfin.mk
include media/qbittorrent/qbittorrent.mk
include media/radarr/radarr.mk
include media/prowlarr/prowlarr.mk
include media/sonarr/sonarr.mk
include media/seerr/seerr.mk
include media/tdarr-server/tdarr-server.mk
include media/tdarr-nodes/tdarr-nodes.mk
include media/decluttarr/decluttarr.mk

# Apps
include app/adguard/adguard.mk
include app/network-multitool/network-multitool.mk
include app/foundry-vtt/foundry-vtt.mk
include app/synology-dsm/synology-dsm.mk
include app/mealie/mealie.mk

# Demos
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
deploy-sys: coredns-deploy democratic-csi-deploy cert-manager-deploy metallb-deploy ingress-internal-deploy ingress-external-deploy oauth2-proxy-deploy loki-deploy fluent-bit-deploy kube-prometheus-stack-deploy
	@echo "Done."

.PHONY: remove-sys
remove-sys: coredns-remove democratic-csi-remove cert-manager-remove metallb-remove ingress-internal-remove ingress-external-remove oauth2-proxy-remove loki-remove fluent-bit-remove kube-prometheus-stack-remove
	@echo "Done."

.PHONY: deploy-apps
deploy-apps: foundry-vtt-deploy jellyfin-deploy network-multitool-deploy synology-dsm-deploy qbittorrent-deploy mealie-deploy seerr-deploy decluttarr-deploy
	@echo "Done."

.PHONY: stop-apps
stop-apps: foundry-vtt-stop jellyfin-stop network-multitool-stop qbittorrent-stop mealie-stop seerr-stop decluttarr-stop
	@echo "Done."

.PHONY: start-apps
start-apps: foundry-vtt-start jellyfin-start network-multitool-start qbittorrent-start mealie-start seerr-start decluttarr-start
	@echo "Done."

.PHONY: remove-apps
remove-apps: foundry-vtt-remove jellyfin-remove network-multitool-remove synology-dsm-remove qbittorrent-remove mealie-remove seerr-remove decluttarr-remove
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

.PHONY: kube-tunnel
kube-tunnel:
	ssh -fNT -L 6443:k3-m1:6443 root@router-public-ip