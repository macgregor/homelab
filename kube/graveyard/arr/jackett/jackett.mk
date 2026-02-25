JACKETT_REPLICAS?=1

.PHONY: jackett-deploy
jackett-deploy:
	kubectl apply -f ./media/jackett/namespace.yml
	kubectl apply -f ./media/jackett/storage.yml
	kubectl apply -f ./media/jackett/network.yml
	kubectl apply -f ./media/jackett/jackett.yml

.PHONY: jackett-remove
jackett-remove:
	-kubectl delete -f ./media/jackett/network.yml
	-kubectl delete -f ./media/jackett/jackett.yml
	-kubectl delete -f ./media/jackett/storage.yml

.PHONY: jackett-debug
jackett-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=jackett -o name` -- bash

.PHONY: jackett-logs
jackett-logs:
	kubectl -n media logs -l app.kubernetes.io/name=jackett --follow --tail=50

.PHONY: jackett-stop
jackett-stop:
	kubectl -n media scale deployment/jackett --replicas=0

.PHONY: jackett-start
jackett-start:
	kubectl -n media scale deployment/jackett --replicas=${JACKETT_REPLICAS}

.PHONY: jackett-restart
jackett-restart:
	kubectl -n media rollout restart deployment/jackett

.PHONY: jackett-status
jackett-status:
	@echo "======================================================================================"
	@echo "= jackett Network Resources:                                                         ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=jackett'    ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=jackett' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= jackett Storage Resources:                                                         ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=jackett'                     ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=jackett' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= jackett Deployment Resources:                                                      ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=jackett'      ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=jackett'
