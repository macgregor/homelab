PROWLARR_REPLICAS?=1

.PHONY: prowlarr-deploy
prowlarr-deploy:
	kubectl apply -f ./app/arr/prowlarr/namespace.yml
	kubectl apply -f ./app/arr/prowlarr/storage.yml
	kubectl apply -f ./app/arr/prowlarr/network.yml
	kubectl apply -f ./app/arr/prowlarr/prowlarr.yml

.PHONY: prowlarr-remove
prowlarr-remove:
	-kubectl delete -f ./app/arr/prowlarr/network.yml
	-kubectl delete -f ./app/arr/prowlarr/prowlarr.yml
	-kubectl delete -f ./app/arr/prowlarr/storage.yml

.PHONY: prowlarr-debug
prowlarr-debug:
	kubectl -n arr exec -it `kubectl -n arr get pods -l app.kubernetes.io/name=prowlarr -o name` -- bash

.PHONY: prowlarr-logs
prowlarr-logs:
	kubectl -n arr logs -l app.kubernetes.io/name=prowlarr --follow --tail=50

.PHONY: prowlarr-stop
prowlarr-stop:
	kubectl -n arr scale deployment/prowlarr --replicas=0

.PHONY: prowlarr-start
prowlarr-start:
	kubectl -n arr scale deployment/prowlarr --replicas=${PROWLARR_REPLICAS}

.PHONY: prowlarr-restart
prowlarr-restart:
	kubectl -n arr rollout restart deployment/prowlarr

.PHONY: prowlarr-status
prowlarr-status:
	@echo "======================================================================================"
	@echo "= prowlarr Network Resources:                                                            ="
	@echo "=   kubectl -n arr get svc,endpoints,ingress -l app.kubernetes.io/name=prowlarr'        ="
	@echo "======================================================================================"
	@kubectl -n arr get svc -l 'app.kubernetes.io/name=prowlarr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n arr get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= prowlarr Storage Resources:                                                            ="
	@echo "=   kubectl -n arr get pvc -l 'app.kubernetes.io/name=prowlarr'                         ="
	@echo "======================================================================================"
	@kubectl -n arr get pvc -l 'app.kubernetes.io/name=prowlarr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= prowlarr Deployment Resources:                                                         ="
	@echo "=   kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=prowlarr'          ="
	@echo "======================================================================================"
	@kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=prowlarr'
