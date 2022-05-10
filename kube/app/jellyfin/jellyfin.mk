JELLYFIN_REPLICAS?=1

.PHONY: jellyfin-deploy
jellyfin-deploy:
	kubectl apply -f ./app/jellyfin/namespace.yml
	kubectl apply -f ./app/jellyfin/storage.yml
	kubectl apply -f ./app/jellyfin/jellyfin.yml
	kubectl apply -f ./app/jellyfin/network.yml

.PHONY: jellyfin-remove
jellyfin-remove:
	-kubectl delete -f ./app/jellyfin/network.yml
	-kubectl delete -f ./app/jellyfin/jellyfin.yml
	-kubectl delete -f ./app/jellyfin/storage.yml
	-kubectl apply -f ./app/jellyfin/namespace.yml --cascade=background

.PHONY: jellyfin-debug
jellyfin-debug:
	kubectl -n jellyfin exec -it `kubectl -n jellyfin get pods -l app.kubernetes.io/name=jellyfin -o name` -- bash

.PHONY: jellyfin-logs
jellyfin-logs:
	#TODO: update
	kubectl -n jellyfin logs `kubectl -n jellyfin get pods -l app.kubernetes.io/name=jellyfin -o name` --follow

.PHONY: jellyfin-stop
jellyfin-stop:
	kubectl -n jellyfin scale deployment/jellyfin --replicas=0

.PHONY: jellyfin-start
jellyfin-start:
	kubectl -n jellyfin scale deployment/jellyfin --replicas=${JELLYFIN_REPLICAS}

.PHONY: jellyfin-restart
jellyfin-restart:
	kubectl -n jellyfin rollout restart deployment/jellyfin

.PHONY: jellyfin-status
jellyfin-status:
	@echo "======================================================================="
	@echo "= jellyfin Network Resources:                                         ="
	@echo "=   kubectl -n jellyfin get svc,endpoints,ingress -l app.kubernetes.io/name=jellyfin'    ="
	@echo "======================================================================="
	@kubectl -n jellyfin get svc -l 'app.kubernetes.io/name=jellyfin' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n jellyfin get endpoints,ingress
	@echo "\n======================================================================="
	@echo "= jellyfin Storage Resources:                                          ="
	@echo "=   kubectl -n jellyfin get pvc -l 'app.kubernetes.io/name=jellyfin'                      ="
	@echo "======================================================================="
	@kubectl -n jellyfin get pvc -l 'app.kubernetes.io/name=jellyfin' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================="
	@echo "= jellyfin Deployment Resources:                                       ="
	@echo "=   kubectl -n jellyfin get deployment,rs,pods -l 'app.kubernetes.io/name=jellyfin'       ="
	@echo "======================================================================="
	@kubectl -n jellyfin get deployment,rs,pods -l 'app.kubernetes.io/name=jellyfin'
