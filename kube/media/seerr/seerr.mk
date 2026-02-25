SEERR_REPLICAS?=1

.PHONY: seerr-deploy
seerr-deploy:
	kubectl apply -f ./media/seerr/namespace.yml
	kubectl apply -f ./media/seerr/storage.yml
	kubectl apply -f ./media/seerr/network.yml
	kubectl apply -f ./media/seerr/seerr.yml

.PHONY: seerr-remove
seerr-remove:
	-kubectl delete -f ./media/seerr/network.yml
	-kubectl delete -f ./media/seerr/seerr.yml
	-kubectl delete -f ./media/seerr/storage.yml

.PHONY: seerr-debug
seerr-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=seerr -o name` -- bash

.PHONY: seerr-logs
seerr-logs:
	kubectl -n media logs -l app.kubernetes.io/name=seerr --follow --tail=50

.PHONY: seerr-stop
seerr-stop:
	kubectl -n media scale deployment/seerr --replicas=0

.PHONY: seerr-start
seerr-start:
	kubectl -n media scale deployment/seerr --replicas=${SEERR_REPLICAS}

.PHONY: seerr-restart
seerr-restart:
	kubectl -n media rollout restart deployment/seerr

.PHONY: seerr-status
seerr-status:
	@echo "======================================================================================"
	@echo "= seerr Network Resources:                                                           ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=seerr'      ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=seerr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= seerr Storage Resources:                                                           ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=seerr'                       ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=seerr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= seerr Deployment Resources:                                                        ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=seerr'        ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=seerr'
