TDARR_NODES_REPLICAS?=1

.PHONY: tdarr-nodes-deploy
tdarr-nodes-deploy:
	kubectl apply -f ./media/tdarr-nodes/namespace.yml
	kubectl apply -f ./media/tdarr-nodes/tdarr-nodes.yml

.PHONY: tdarr-nodes-remove
tdarr-nodes-remove:
	-kubectl delete -f ./media/tdarr-nodes/tdarr-nodes.yml

.PHONY: tdarr-nodes-debug
tdarr-nodes-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=tdarr-nodes -o name` -- bash

.PHONY: tdarr-nodes-logs
tdarr-nodes-logs:
	kubectl -n media logs -l app.kubernetes.io/name=tdarr-nodes --follow

.PHONY: tdarr-nodes-stop
tdarr-nodes-stop:
	kubectl -n media scale statefulset/tdarr-nodes --replicas=0

.PHONY: tdarr-nodes-start
tdarr-nodes-start:
	kubectl -n media scale statefulset/tdarr-nodes --replicas=${TDARR_NODES_REPLICAS}

.PHONY: tdarr-nodes-restart
tdarr-nodes-restart:
	kubectl -n media rollout restart statefulset/tdarr-nodes

.PHONY: tdarr-nodes-status
tdarr-nodes-status:
	@echo "======================================================================================"
	@echo "= tdarr-nodes Network Resources:                                                            ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=tdarr-nodes'        ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=tdarr-nodes' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= tdarr-nodes Storage Resources:                                                            ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=tdarr-nodes'                         ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=tdarr-nodes' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= tdarr-nodes Deployment Resources:                                                         ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=tdarr-nodes'          ="
	@echo "======================================================================================"
	@kubectl -n media get statefulset,deployment,rs,pods -l 'app.kubernetes.io/name=tdarr-nodes'
