RADARR_REPLICAS?=1

.PHONY: radarr-deploy
radarr-deploy:
	kubectl apply -f ./media/radarr/namespace.yml
	kubectl apply -f ./media/radarr/storage.yml
	kubectl apply -f ./media/radarr/network.yml
	kubectl apply -f ./media/radarr/radarr.yml
	kubectl create secret generic radarr-api-key \
		-n media \
		--save-config \
		--dry-run=client \
		--from-literal=RADARR_API_KEY="${RADARR_API_KEY}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./media/radarr/cronjob.yml

.PHONY: radarr-remove
radarr-remove:
	-kubectl delete -f ./media/radarr/cronjob.yml
	-kubectl -n media delete secret/radarr-api-key
	-kubectl delete -f ./media/radarr/network.yml
	-kubectl delete -f ./media/radarr/radarr.yml
	-kubectl delete -f ./media/radarr/storage.yml

.PHONY: radarr-debug
radarr-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=radarr -o name` -- bash

.PHONY: radarr-logs
radarr-logs:
	kubectl -n media logs -l app.kubernetes.io/name=radarr --follow --tail=50

.PHONY: radarr-stop
radarr-stop:
	kubectl -n media scale deployment/radarr --replicas=0

.PHONY: radarr-start
radarr-start:
	kubectl -n media scale deployment/radarr --replicas=${RADARR_REPLICAS}

.PHONY: radarr-restart
radarr-restart:
	kubectl -n media rollout restart deployment/radarr

.PHONY: radarr-search
radarr-search:
	kubectl -n media create job --from=cronjob/radarr-missing-search radarr-missing-search-manual-$$(date +%s)

.PHONY: radarr-status
radarr-status:
	@echo "======================================================================================"
	@echo "= radarr Network Resources:                                                          ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=radarr'     ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=radarr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= radarr Storage Resources:                                                          ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=radarr'                      ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=radarr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= radarr Deployment Resources:                                                       ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=radarr'       ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=radarr'
	@echo -e "\n======================================================================================"
	@echo "= radarr CronJob Resources:                                                          ="
	@echo "=   kubectl -n media get cronjobs,jobs -l 'app.kubernetes.io/name=radarr'            ="
	@echo "======================================================================================"
	@kubectl -n media get cronjobs,jobs -l 'app.kubernetes.io/name=radarr'
