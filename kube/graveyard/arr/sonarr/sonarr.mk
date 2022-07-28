SONARR_REPLICAS?=1

.PHONY: sonarr-deploy
sonarr-deploy:
	kubectl apply -f ./app/arr/sonarr/namespace.yml
	kubectl apply -f ./app/arr/sonarr/storage.yml
	kubectl apply -f ./app/arr/sonarr/network.yml
	kubectl apply -f ./app/arr/sonarr/sonarr.yml

.PHONY: sonarr-remove
sonarr-remove:
	-kubectl delete -f ./app/arr/sonarr/network.yml
	-kubectl delete -f ./app/arr/sonarr/sonarr.yml
	-kubectl delete -f ./app/arr/sonarr/storage.yml

.PHONY: sonarr-debug
sonarr-debug:
	kubectl -n arr exec -it `kubectl -n arr get pods -l app.kubernetes.io/name=sonarr -o name` -- bash

.PHONY: sonarr-logs
sonarr-logs:
	kubectl -n arr logs -l app.kubernetes.io/name=sonarr --follow

.PHONY: sonarr-stop
sonarr-stop:
	kubectl -n arr scale deployment/sonarr --replicas=0

.PHONY: sonarr-start
sonarr-start:
	kubectl -n arr scale deployment/sonarr --replicas=${SONARR_REPLICAS}

.PHONY: sonarr-restart
sonarr-restart:
	kubectl -n arr rollout restart deployment/sonarr

.PHONY: sonarr-status
sonarr-status:
	@echo "======================================================================================"
	@echo "= sonarr Network Resources:                                                            ="
	@echo "=   kubectl -n arr get svc,endpoints,ingress -l app.kubernetes.io/name=sonarr'        ="
	@echo "======================================================================================"
	@kubectl -n arr get svc -l 'app.kubernetes.io/name=sonarr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n arr get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= sonarr Storage Resources:                                                            ="
	@echo "=   kubectl -n arr get pvc -l 'app.kubernetes.io/name=sonarr'                         ="
	@echo "======================================================================================"
	@kubectl -n arr get pvc -l 'app.kubernetes.io/name=sonarr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= sonarr Deployment Resources:                                                         ="
	@echo "=   kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=sonarr'          ="
	@echo "======================================================================================"
	@kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=sonarr'
