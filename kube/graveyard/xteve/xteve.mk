XTEVE_REPLICAS?=1

.PHONY: xteve-deploy
xteve-deploy:
	kubectl apply -f ./media/xteve/namespace.yml
	kubectl apply -f ./media/xteve/storage.yml
	helmfile --file ./media/xteve/helmfile.yaml apply

.PHONY: xteve-remove
xteve-remove:
	-helmfile --file ./media/xteve/helmfile.yaml destroy
	-kubectl delete -f ./media/xteve/storage.yml

.PHONY: xteve-debug
xteve-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=xteve -o name` -- bash

.PHONY: xteve-logs
xteve-logs:
	#TODO: update
	kubectl -n media logs `kubectl -n media get pods -l app.kubernetes.io/name=xteve -o name` --follow

.PHONY: xteve-stop
xteve-stop:
	kubectl -n media scale deployment/xteve --replicas=0

.PHONY: xteve-start
xteve-start:
	kubectl -n media scale deployment/xteve --replicas=${XTEVE_REPLICAS}

.PHONY: xteve-restart
xteve-restart:
	kubectl -n media rollout restart deployment/xteve

.PHONY: xteve-status
xteve-status:
	@echo "======================================================================================"
	@echo "= xteve Network Resources:                                                           ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=xteve'      ="
	@echo "======================================================================================"
	@kubectl -n media get svc -l 'app.kubernetes.io/name=xteve' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress -l 'app.kubernetes.io/name=xteve'
	@echo -e "\n======================================================================================"
	@echo "= xteve Storage Resources:                                                           ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=xteve'                       ="
	@echo "======================================================================================"
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=xteve' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= xteve Deployment Resources:                                                        ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=xteve'        ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=xteve'
