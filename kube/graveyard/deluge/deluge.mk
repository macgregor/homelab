DELUGE_REPLICAS?=1

.PHONY: deluge-deploy
deluge-deploy:
	kubectl apply -f ./media/deluge/namespace.yml
	kubectl create secret generic deluge-vpn-credentials \
		-n media \
		--save-config \
		--dry-run=client \
		--from-literal=WIREGUARD_PRIVATE_KEY="${WIREGUARD_PRIVATE_KEY}" \
		--from-literal=OPENVPN_USER="${VPN_USERNAME}" \
		--from-literal=OPENVPN_PASSWORD="${VPN_PASSWORD}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./media/deluge/storage.yml
	kubectl apply -f ./media/deluge/network.yml
	kubectl apply -f ./media/deluge/deluge.yml

.PHONY: deluge-remove
deluge-remove:
	-kubectl delete -f ./media/deluge/network.yml
	-kubectl delete -f ./media/deluge/deluge.yml
	-kubectl delete -f ./media/deluge/storage.yml
	-kubectl -n media delete secret/vpn-credentials

.PHONY: deluge-debug
deluge-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=deluge -o name` -- bash

.PHONY: deluge-logs
deluge-logs:
	kubectl -n media logs -l app.kubernetes.io/name=deluge --follow

.PHONY: deluge-stop
deluge-stop:
	kubectl -n media scale deployment/deluge --replicas=0

.PHONY: deluge-start
deluge-start:
	kubectl -n media scale deployment/deluge --replicas=${deluge_REPLICAS}

.PHONY: deluge-restart
deluge-restart:
	kubectl -n media rollout restart deployment/deluge

.PHONY: deluge-status
deluge-status:
	@echo "======================================================================================"
	@echo "= deluge Network Resources:                                                            ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=deluge'        ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=deluge' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress -l 'app.kubernetes.io/name=deluge'
	@echo "\n======================================================================================"
	@echo "= deluge Storage Resources:                                                            ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=deluge'                         ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=deluge' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= deluge Deployment Resources:                                                         ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=deluge'          ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=deluge'
