RADARR_REPLICAS?=1

.PHONY: radarr-deploy
radarr-deploy:
	kubectl apply -f ./app/arr/radarr/namespace.yml
	kubectl apply -f ./app/arr/radarr/storage.yml
	kubectl apply -f ./app/arr/radarr/network.yml
	kubectl apply -f ./app/arr/radarr/radarr.yml

.PHONY: radarr-remove
radarr-remove:
	-kubectl delete -f ./app/arr/radarr/network.yml
	-kubectl delete -f ./app/arr/radarr/radarr.yml
	-kubectl delete -f ./app/arr/radarr/storage.yml

.PHONY: radarr-debug
radarr-debug:
	kubectl -n arr exec -it `kubectl -n arr get pods -l app.kubernetes.io/name=radarr -o name` -- bash

.PHONY: radarr-logs
radarr-logs:
	kubectl -n arr logs -l app.kubernetes.io/name=radarr --follow --tail=50

.PHONY: radarr-stop
radarr-stop:
	kubectl -n arr scale deployment/radarr --replicas=0

.PHONY: radarr-start
radarr-start:
	kubectl -n arr scale deployment/radarr --replicas=${RADARR_REPLICAS}

.PHONY: radarr-restart
radarr-restart:
	kubectl -n arr rollout restart deployment/radarr

.PHONY: radarr-status
radarr-status:
	@echo "======================================================================================"
	@echo "= radarr Network Resources:                                                            ="
	@echo "=   kubectl -n arr get svc,endpoints,ingress -l app.kubernetes.io/name=radarr'        ="
	@echo "======================================================================================"
	@kubectl -n arr get svc -l 'app.kubernetes.io/name=radarr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n arr get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= radarr Storage Resources:                                                            ="
	@echo "=   kubectl -n arr get pvc -l 'app.kubernetes.io/name=radarr'                         ="
	@echo "======================================================================================"
	@kubectl -n arr get pvc -l 'app.kubernetes.io/name=radarr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= radarr Deployment Resources:                                                         ="
	@echo "=   kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=radarr'          ="
	@echo "======================================================================================"
	@kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=radarr'
