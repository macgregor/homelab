QBITTORRENT_REPLICAS?=1

.PHONY: qbittorrent-deploy
qbittorrent-deploy:
	kubectl apply -f ./app/arr/qbittorrent/namespace.yml
	kubectl create secret generic vpn-credentials \
		-n arr \
		--save-config \
		--dry-run=client \
		--from-literal=VPN_USERNAME="${VPN_USERNAME}" \
		--from-literal=VPN_PASSWORD="${VPN_PASSWORD}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./app/arr/qbittorrent/storage.yml
	kubectl apply -f ./app/arr/qbittorrent/network.yml
	kubectl apply -f ./app/arr/qbittorrent/qbittorrent.yml

.PHONY: qbittorrent-remove
qbittorrent-remove:
	-kubectl delete -f ./app/arr/qbittorrent/network.yml
	-kubectl delete -f ./app/arr/qbittorrent/qbittorrent.yml
	-kubectl delete -f ./app/arr/qbittorrent/storage.yml
	-kubectl -n arr delete secret/vpn-credentials

.PHONY: qbittorrent-debug
qbittorrent-debug:
	kubectl -n arr exec -it `kubectl -n arr get pods -l app.kubernetes.io/name=qbittorrent -o name` -- bash

.PHONY: qbittorrent-logs
qbittorrent-logs:
	kubectl -n arr logs -l app.kubernetes.io/name=qbittorrent --follow

.PHONY: qbittorrent-stop
qbittorrent-stop:
	kubectl -n arr scale deployment/qbittorrent --replicas=0

.PHONY: qbittorrent-start
qbittorrent-start:
	kubectl -n arr scale deployment/qbittorrent --replicas=${QBITTORRENT_REPLICAS}

.PHONY: qbittorrent-restart
qbittorrent-restart:
	kubectl -n arr rollout restart deployment/qbittorrent

.PHONY: qbittorrent-status
qbittorrent-status:
	@echo "======================================================================================"
	@echo "= qbittorrent Network Resources:                                                            ="
	@echo "=   kubectl -n arr get svc,endpoints,ingress -l app.kubernetes.io/name=qbittorrent'        ="
	@echo "======================================================================================"
	@kubectl -n arr get svc -l 'app.kubernetes.io/name=qbittorrent' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n arr get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= qbittorrent Storage Resources:                                                            ="
	@echo "=   kubectl -n arr get pvc -l 'app.kubernetes.io/name=qbittorrent'                         ="
	@echo "======================================================================================"
	@kubectl -n arr get pvc -l 'app.kubernetes.io/name=qbittorrent' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= qbittorrent Deployment Resources:                                                         ="
	@echo "=   kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=qbittorrent'          ="
	@echo "======================================================================================"
	@kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=qbittorrent'
