TAILSCALE_REPLICAS?=1

.PHONY: tailscale-deploy
tailscale-deploy:
	kubectl apply -f ./app/tailscale/namespace.yml
	kubectl apply -f ./app/tailscale/rbac.yml
	kubectl create secret generic tailscale-auth \
		-n tailscale \
		--save-config \
		--dry-run=client \
		--from-literal=TS_AUTH_KEY="${TS_AUTH_KEY}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./app/tailscale/tailscale-pod.yml

.PHONY: tailscale-remove
tailscale-remove:
	-kubectl delete -f ./app/tailscale/tailscale.yml
	-kubectl delete -f ./app/tailscale/rbac.yml
	-kubectl -n tailscale delete secret/tailscale-auth

.PHONY: tailscale-debug
tailscale-debug:
	kubectl -n tailscale exec -it `kubectl -n tailscale get pods -l app.kubernetes.io/name=tailscale -o name` -- bash

.PHONY: tailscale-logs
tailscale-logs:
	kubectl -n tailscale logs -l app.kubernetes.io/name=tailscale --follow

.PHONY: tailscale-stop
tailscale-stop:
	kubectl -n tailscale scale deployment/tailscale-subnet-router --replicas=0

.PHONY: tailscale-start
tailscale-start:
	kubectl -n tailscale scale deployment/tailscale-subnet-router --replicas=${TAILSCALE_REPLICAS}

.PHONY: tailscale-restart
tailscale-restart:
	kubectl -n tailscale rollout restart deployment/tailscale-subnet-router

.PHONY: tailscale-status
tailscale-status:
	@echo "======================================================================================"
	@echo "= tailscale Network Resources:                                                            ="
	@echo "=   kubectl -n tailscale get svc,endpoints,ingress -l app.kubernetes.io/name=tailscale'        ="
	@echo "======================================================================================"
	@kubectl -n tailscale get svc -l 'app.kubernetes.io/name=tailscale' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n tailscale get endpoints,ingress -l 'app.kubernetes.io/name=tailscale'
	@echo "\n======================================================================================"
	@echo "= tailscale Storage Resources:                                                            ="
	@echo "=   kubectl -n tailscale get pvc -l 'app.kubernetes.io/name=tailscale'                         ="
	@echo "======================================================================================"
	@kubectl -n tailscale get pvc -l 'app.kubernetes.io/name=tailscale' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= tailscale Deployment Resources:                                                         ="
	@echo "=   kubectl -n tailscale get deployment,rs,pods -l 'app.kubernetes.io/name=tailscale'          ="
	@echo "======================================================================================"
	@kubectl -n tailscale get deployment,rs,pods -l 'app.kubernetes.io/name=tailscale'
