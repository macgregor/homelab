SONARR_REPLICAS?=1

.PHONY: sonarr-deploy
sonarr-deploy:
	kubectl apply -f ./media/sonarr/namespace.yml
	kubectl apply -f ./media/sonarr/storage.yml
	kubectl apply -f ./media/sonarr/network.yml
	kubectl apply -f ./media/sonarr/sonarr.yml
	kubectl create secret generic sonarr-api-key \
		-n media \
		--save-config \
		--dry-run=client \
		--from-literal=SONARR_API_KEY="${SONARR_API_KEY}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./media/sonarr/cronjob.yml

.PHONY: sonarr-remove
sonarr-remove:
	-kubectl delete -f ./media/sonarr/cronjob.yml
	-kubectl -n media delete secret/sonarr-api-key
	-kubectl delete -f ./media/sonarr/network.yml
	-kubectl delete -f ./media/sonarr/sonarr.yml
	-kubectl delete -f ./media/sonarr/storage.yml

.PHONY: sonarr-debug
sonarr-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=sonarr -o name` -- bash

.PHONY: sonarr-logs
sonarr-logs:
	kubectl -n media logs -l app.kubernetes.io/name=sonarr --follow

.PHONY: sonarr-stop
sonarr-stop:
	kubectl -n media scale deployment/sonarr --replicas=0

.PHONY: sonarr-start
sonarr-start:
	kubectl -n media scale deployment/sonarr --replicas=${SONARR_REPLICAS}

.PHONY: sonarr-restart
sonarr-restart:
	kubectl -n media rollout restart deployment/sonarr

.PHONY: sonarr-search
sonarr-search:
	kubectl -n media create job --from=cronjob/sonarr-missing-search sonarr-missing-search-manual-$$(date +%s)

.PHONY: sonarr-status
sonarr-status:
	@echo "======================================================================================"
	@echo "= sonarr Network Resources:                                                          ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=sonarr'     ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=sonarr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= sonarr Storage Resources:                                                          ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=sonarr'                      ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=sonarr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= sonarr Deployment Resources:                                                       ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=sonarr'       ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=sonarr'
	@echo -e "\n======================================================================================"
	@echo "= sonarr CronJob Resources:                                                          ="
	@echo "=   kubectl -n media get cronjobs,jobs -l 'app.kubernetes.io/name=sonarr'            ="
	@echo "======================================================================================"
	@kubectl -n media get cronjobs,jobs -l 'app.kubernetes.io/name=sonarr'
