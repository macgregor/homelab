claim?=${PLEX_CLAIM}

.PHONY: plex-deploy
plex-deploy:
	kubectl apply -f ./plex/namespace.yml
	kubectl apply -f ./plex/storage.yml
	@if [ "${claim}" != "" ]; then \
	kubectl create secret generic plex-claim-token \
		--save-config \
		--dry-run=client \
		--from-literal=token="${claim}" \
		-o yaml | kubectl apply -f -; \
	else echo 'No claim token found. Retrieve a token from plex.tv/claim/ and set with make plex-deploy claim=foo or export PLEX_CLAIM=foo'; \
  fi
	kubectl apply -f ./plex/plex.yml
	kubectl apply -f ./plex/network.yml

.PHONY: plex-remove
plex-remove:
	-kubectl delete -f ./plex/network.yml
	-kubectl delete -f ./plex/plex.yml
	-kubectl -n plex delete secret/plex-claim-token
	-kubectl delete -f ./plex/storage.yml
	-kubectl delete -f ./plex/namespace.yml --cascade=background

.PHONY: plex-debug
plex-debug:
	kubectl -n plex exec -it `kubectl -n plex get pods -l app=plexserver -o name` -- bash

.PHONY: plex-logs
plex-logs:
	kubectl -n plex exec -it `kubectl -n plex get pods -l app=plexserver -o name` -- tail "/config/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log" --follow

.PHONY: plex-ingress-logs
plex-ingress-logs:
	kubectl -n ingress-nginx logs deployment/ingress-nginx-controller | grep plex

.PHONY: plex-stop
plex-stop:
	kubectl -n plex scale deployment/plex --replicas=0

.PHONY: plex-start
plex-start:
	kubectl -n plex scale deployment/plex --replicas=${PLEX_REPLICAS}

.PHONY: plex-restart
plex-restart:
	kubectl -n plex rollout restart deployment/plex

.PHONY: plex-status
plex-status:
	@echo "======================================================================="
	@echo "= Plex Network Resources:                                             ="
	@echo "=   kubectl -n plex get svc,endpoints,ingress -l app=plexserver'      ="
	@echo "======================================================================="
	@kubectl -n plex get svc -l 'app=plexserver' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP --show-kind
	@echo ""
	@kubectl -n plex get endpoints,ingress
	@echo -e "\n======================================================================="
	@echo "= Plex Storage Resources:                                             ="
	@echo "=   kubectl -n plex get pvc -l 'app=plexserver'                       ="
	@echo "======================================================================="
	@kubectl -n plex get pvc -l 'app=plexserver' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= Plex Deployment Resources:                                          ="
	@echo "=   kubectl -n plex get deployment,rs,pods -l 'app=plexserver'        ="
	@echo "======================================================================="
	@kubectl -n plex get deployment,rs,pods -l 'app=plexserver'


.PHONY: plex-claim-token
plex-claim-token:
