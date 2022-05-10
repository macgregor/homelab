WHOAMI_REPLICAS?=1

.PHONY: whoami-deploy
whoami-deploy:
	kubectl apply -f ./demo/whoami/namespace.yml
	kubectl apply -f ./demo/whoami/network.yml
	kubectl apply -f ./demo/whoami/whoami.yml

.PHONY: whoami-remove
whoami-remove:
	-kubectl delete -f ./demo/whoami/whoami.yml
	-kubectl delete -f ./demo/whoami/network.yml
	-kubectl delete -f ./demo/whoami/namespace.yml --cascade=background

.PHONY: whoami-debug
whoami-debug:
	kubectl -n whoami exec -it `kubectl -n whoami get pods -l app.kubernetes.io/name=whoami -o name | head -n 1` -- bash

.PHONY: whoami-logs
whoami-logs:
	@echo "TODO"

.PHONY: whoami-stop
whoami-stop:
	kubectl -n whoami scale deployment/whoami --replicas=0

.PHONY: whoami-start
whoami-start:
	kubectl -n whoami scale deployment/whoami --replicas=${WHOAMI_REPLICAS}

.PHONY: whoami-restart
whoami-restart:
	kubectl -n whoami rollout restart deployment/whoami

.PHONY: whoami-status
whoami-status:
	@echo "======================================================================="
	@echo "= whoami Network Resources:                                         ="
	@echo "=   kubectl -n whoami get svc,endpoints,ingress -l app.kubernetes.io/name=whoami'    ="
	@echo "======================================================================="
	@kubectl -n whoami get svc -l 'app.kubernetes.io/name=whoami' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n whoami get endpoints,ingress
	@echo "\n======================================================================="
	@echo "= whoami Storage Resources:                                          ="
	@echo "=   kubectl -n whoami get pvc -l 'app=whoami'                      ="
	@echo "======================================================================="
	@kubectl -n whoami-multitool get pvc -l 'app.kubernetes.io/name=whoami' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================="
	@echo "= whoami Deployment Resources:                                       ="
	@echo "=   kubectl -n whoami get deployment,rs,pods -l 'app.kubernetes.io/name=whoami'       ="
	@echo "======================================================================="
	@kubectl -n whoami get deployment,rs,pods -l 'app.kubernetes.io/name=whoami'
