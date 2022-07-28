JACKETT_REPLICAS?=1

.PHONY: jackett-deploy
jackett-deploy:
	kubectl apply -f ./app/arr/jackett/namespace.yml
	kubectl apply -f ./app/arr/jackett/storage.yml
	kubectl apply -f ./app/arr/jackett/network.yml
	kubectl apply -f ./app/arr/jackett/jackett.yml

.PHONY: jackett-remove
jackett-remove:
	-kubectl delete -f ./app/arr/jackett/network.yml
	-kubectl delete -f ./app/arr/jackett/jackett.yml
	-kubectl delete -f ./app/arr/jackett/storage.yml

.PHONY: jackett-debug
jackett-debug:
	kubectl -n arr exec -it `kubectl -n arr get pods -l app.kubernetes.io/name=jackett -o name` -- bash

.PHONY: jackett-logs
jackett-logs:
	kubectl -n arr logs -l app.kubernetes.io/name=jackett --follow --tail=50

.PHONY: jackett-stop
jackett-stop:
	kubectl -n arr scale deployment/jackett --replicas=0

.PHONY: jackett-start
jackett-start:
	kubectl -n arr scale deployment/jackett --replicas=${JACKETT_REPLICAS}

.PHONY: jackett-restart
jackett-restart:
	kubectl -n arr rollout restart deployment/jackett

.PHONY: jackett-status
jackett-status:
	@echo "======================================================================================"
	@echo "= jackett Network Resources:                                                            ="
	@echo "=   kubectl -n arr get svc,endpoints,ingress -l app.kubernetes.io/name=jackett'        ="
	@echo "======================================================================================"
	@kubectl -n arr get svc -l 'app.kubernetes.io/name=jackett' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n arr get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= jackett Storage Resources:                                                            ="
	@echo "=   kubectl -n arr get pvc -l 'app.kubernetes.io/name=jackett'                         ="
	@echo "======================================================================================"
	@kubectl -n arr get pvc -l 'app.kubernetes.io/name=jackett' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= jackett Deployment Resources:                                                         ="
	@echo "=   kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=jackett'          ="
	@echo "======================================================================================"
	@kubectl -n arr get deployment,rs,pods -l 'app.kubernetes.io/name=jackett'
