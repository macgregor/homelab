TDARR_SERVER_REPLICAS?=1

.PHONY: tdarr-server-deploy
tdarr-server-deploy:
	kubectl apply -f ./media/tdarr-server/namespace.yml
	kubectl apply -f ./media/tdarr-server/storage.yml
	kubectl apply -f ./media/tdarr-server/network.yml
	kubectl apply -f ./media/tdarr-server/tdarr-server.yml

.PHONY: tdarr-server-remove
tdarr-server-remove:
	-kubectl delete -f ./media/tdarr-server/network.yml
	-kubectl delete -f ./media/tdarr-server/tdarr-server.yml
	-kubectl delete -f ./media/tdarr-server/storage.yml

.PHONY: tdarr-server-debug
tdarr-server-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=tdarr-server -o name` -- bash

.PHONY: tdarr-server-logs
tdarr-server-logs:
	kubectl -n media logs -l app.kubernetes.io/name=tdarr-server --follow

.PHONY: tdarr-server-stop
tdarr-server-stop:
	kubectl -n media scale deployment/tdarr-server --replicas=0

.PHONY: tdarr-server-start
tdarr-server-start:
	kubectl -n media scale deployment/tdarr-server --replicas=${TDARR_SERVER_REPLICAS}

.PHONY: tdarr-server-restart
tdarr-server-restart:
	kubectl -n media rollout restart deployment/tdarr-server

.PHONY: tdarr-server-status
tdarr-server-status:
	@echo "======================================================================================"
	@echo "= tdarr-server Network Resources:                                                            ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=tdarr-server'        ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=tdarr-server' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= tdarr-server Storage Resources:                                                            ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=tdarr-server'                         ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=tdarr-server' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= tdarr-server Deployment Resources:                                                         ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=tdarr-server'          ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=tdarr-server'
