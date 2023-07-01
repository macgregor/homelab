QBITTORRENT_REPLICAS?=1

.PHONY: qbittorrent-deploy
qbittorrent-deploy:
	kubectl apply -f ./media/qbittorrent/namespace.yml
	kubectl create secret generic vpn-credentials \
		-n media \
		--save-config \
		--dry-run=client \
		--from-literal=WIREGUARD_PRIVATE_KEY="${WIREGUARD_PRIVATE_KEY}" \
		--from-literal=OPENVPN_USER="${VPN_USERNAME}" \
		--from-literal=OPENVPN_PASSWORD="${VPN_PASSWORD}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./media/qbittorrent/storage.yml
	kubectl apply -f ./media/qbittorrent/network.yml
	kubectl apply -f ./media/qbittorrent/qbittorrent.yml

.PHONY: qbittorrent-remove
qbittorrent-remove:
	-kubectl delete -f ./media/qbittorrent/network.yml
	-kubectl delete -f ./media/qbittorrent/qbittorrent.yml
	-kubectl delete -f ./media/qbittorrent/storage.yml
	-kubectl -n media delete secret/vpn-credentials

.PHONY: qbittorrent-debug
qbittorrent-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=qbittorrent -o name` -- bash

.PHONY: qbittorrent-logs
qbittorrent-logs:
	kubectl -n media logs -l app.kubernetes.io/name=qbittorrent --follow

.PHONY: qbittorrent-stop
qbittorrent-stop:
	kubectl -n media scale deployment/qbittorrent --replicas=0

.PHONY: qbittorrent-start
qbittorrent-start:
	kubectl -n media scale deployment/qbittorrent --replicas=${QBITTORRENT_REPLICAS}

.PHONY: qbittorrent-restart
qbittorrent-restart:
	kubectl -n media rollout restart deployment/qbittorrent

.PHONY: qbittorrent-status
qbittorrent-status:
	@echo "======================================================================================"
	@echo "= qbittorrent Network Resources:                                                            ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=qbittorrent'        ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=qbittorrent' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress -l 'app.kubernetes.io/name=qbittorrent'
	@echo "\n======================================================================================"
	@echo "= qbittorrent Storage Resources:                                                            ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=qbittorrent'                         ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=qbittorrent' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= qbittorrent Deployment Resources:                                                         ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=qbittorrent'          ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=qbittorrent'
