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
	kubectl -n demo exec -it `kubectl -n demo get pods -l app.kubernetes.io/name=kuard -o name | head -n 1` -- bash

.PHONY: kuard-logs
kuard-logs:
	@echo "TODO"

.PHONY: kuard-stop
kuard-stop:
	kubectl -n demo scale deployment/kuard --replicas=0

.PHONY: kuard-start
kuard-start:
	kubectl -n demo scale deployment/kuard --replicas=${KUARD_REPLICAS}

.PHONY: kuard-restart
kuard-restart:
	kubectl -n demo rollout restart deployment/kuard

.PHONY: kuard-status
kuard-status:
	@echo "======================================================================="
	@echo "= kuard Network Resources:                                            ="
	@echo "=   kubectl -n demo get svc,endpoints,ingress -l app.kubernetes.io/name=kuard' ="
	@echo "======================================================================="
	@kubectl -n demo get svc -l 'app.kubernetes.io/name=kuard' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n demo get endpoints,ingress
	@echo -e "\n======================================================================="
	@echo "= kuard Storage Resources:                                            ="
	@echo "=   kubectl -n demo get pvc -l 'app=kuard'                            ="
	@echo "======================================================================="
	@kubectl -n demo-multitool get pvc -l 'app.kubernetes.io/name=kuard' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= kuard Deployment Resources:                                         ="
	@echo "=   kubectl -n demo get deployment,rs,pods -l 'app.kubernetes.io/name=kuard' ="
	@echo "======================================================================="
	@kubectl -n demo get deployment,rs,pods -l 'app.kubernetes.io/name=kuard'
