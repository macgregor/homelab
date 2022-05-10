KUARD_REPLICAS?=1

.PHONY: kuard-deploy
kuard-deploy:
	kubectl apply -f ./demo/kuard/namespace.yml
	kubectl apply -f ./demo/kuard/network.yml
	kubectl apply -f ./demo/kuard/kuard.yml

.PHONY: kuard-remove
kuard-remove:
	-kubectl delete -f ./demo/kuard/kuard.yml
	-kubectl delete -f ./demo/kuard/network.yml
	-kubectl delete -f ./demo/kuard/namespace.yml --cascade=background

.PHONY: kuard-debug
kuard-debug:
	kubectl -n kuard exec -it `kubectl -n kuard get pods -l app.kubernetes.io/name=kuard -o name | head -n 1` -- bash

.PHONY: kuard-logs
kuard-logs:
	@echo "TODO"

.PHONY: kuard-stop
kuard-stop:
	kubectl -n kuard scale deployment/kuard --replicas=0

.PHONY: kuard-start
kuard-start:
	kubectl -n kuard scale deployment/kuard --replicas=${KUARD_REPLICAS}

.PHONY: kuard-restart
kuard-restart:
	kubectl -n kuard rollout restart deployment/kuard

.PHONY: kuard-status
kuard-status:
	@echo "======================================================================="
	@echo "= kuard Network Resources:                                         ="
	@echo "=   kubectl -n kuard get svc,endpoints,ingress -l app.kubernetes.io/name=kuard'    ="
	@echo "======================================================================="
	@kubectl -n kuard get svc -l 'app.kubernetes.io/name=kuard' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n kuard get endpoints,ingress
	@echo "\n======================================================================="
	@echo "= kuard Storage Resources:                                          ="
	@echo "=   kubectl -n kuard get pvc -l 'app=kuard'                      ="
	@echo "======================================================================="
	@kubectl -n kuard-multitool get pvc -l 'app.kubernetes.io/name=kuard' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================="
	@echo "= kuard Deployment Resources:                                       ="
	@echo "=   kubectl -n kuard get deployment,rs,pods -l 'app.kubernetes.io/name=kuard'       ="
	@echo "======================================================================="
	@kubectl -n kuard get deployment,rs,pods -l 'app.kubernetes.io/name=kuard'
