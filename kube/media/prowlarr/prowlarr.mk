PROWLARR_REPLICAS?=1

.PHONY: prowlarr-deploy
prowlarr-deploy:
	kubectl apply -f ./media/prowlarr/namespace.yml
	kubectl apply -f ./media/prowlarr/storage.yml
	kubectl apply -f ./media/prowlarr/network.yml
	kubectl apply -f ./media/prowlarr/prowlarr.yml

.PHONY: prowlarr-remove
prowlarr-remove:
	-kubectl delete -f ./media/prowlarr/network.yml
	-kubectl delete -f ./media/prowlarr/prowlarr.yml
	-kubectl delete -f ./media/prowlarr/storage.yml

.PHONY: prowlarr-debug
prowlarr-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=prowlarr -o name` -- bash

.PHONY: prowlarr-logs
prowlarr-logs:
	kubectl -n media logs -l app.kubernetes.io/name=prowlarr --follow --tail=50

.PHONY: prowlarr-stop
prowlarr-stop:
	kubectl -n media scale deployment/prowlarr --replicas=0

.PHONY: prowlarr-start
prowlarr-start:
	kubectl -n media scale deployment/prowlarr --replicas=${PROWLARR_REPLICAS}

.PHONY: prowlarr-restart
prowlarr-restart:
	kubectl -n media rollout restart deployment/prowlarr

.PHONY: prowlarr-status
prowlarr-status:
	@echo "======================================================================================"
	@echo "= prowlarr Network Resources:                                                        ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=prowlarr'   ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=prowlarr' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= prowlarr Storage Resources:                                                        ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=prowlarr'                    ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=prowlarr' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= prowlarr Deployment Resources:                                                     ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=prowlarr'     ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=prowlarr'
