COREDNS_REPLICAS?=2

.PHONY: coredns-deploy
coredns-deploy:
	kubectl apply -f ./sys/coredns/roles.yml
	kubectl apply -f ./sys/coredns/coredns.yml
	kubectl apply -f ./sys/coredns/network.yml

.PHONY: coredns-remove
coredns-remove:
	-kubectl delete -f ./sys/coredns/coredns.yml

.PHONY: coredns-debug
coredns-debug:
	kubectl -n kube-system exec -it `kubectl -n kube-system get pods -l app.kubernetes.io/name=coredns -o name | head -n 1` -- bash

.PHONY: coredns-logs
coredns-logs:
	#TODO: update
	kubectl -n kube-system logs `kubectl -n kube-system get pods -l app.kubernetes.io/name=coredns -o name | head -n 1` --follow

.PHONY: coredns-stop
coredns-stop:
	kubectl -n kube-system scale deployment/coredns --replicas=0

.PHONY: coredns-start
coredns-start:
	kubectl -n kube-system scale deployment/coredns --replicas=${COREDNS_REPLICAS}

.PHONY: coredns-restart
coredns-restart:
	kubectl -n kube-system rollout restart deployment/coredns

.PHONY: coredns-status
coredns-status:
	@echo "======================================================================="
	@echo "= coredns Network Resources:                                          ="
	@echo "=   kubectl -n kube-system get svc,endpoints,ingress -l app.kubernetes.io/name=coredns' ="
	@echo "======================================================================="
	@kubectl -n kube-system get svc -l 'app.kubernetes.io/name=coredns' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n kube-system get endpoints,ingress -l 'app.kubernetes.io/name=coredns'
	@echo -e "\n======================================================================="
	@echo "= coredns Storage Resources:                                          ="
	@echo "=   kubectl -n kube-system get pvc -l 'app.kubernetes.io/name=coredns' ="
	@echo "======================================================================="
	@kubectl -n kube-system get pvc -l 'app.kubernetes.io/name=coredns' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= coredns Deployment Resources:                                       ="
	@echo "=   kubectl -n kube-system get deployment,rs,pods -l 'app.kubernetes.io/name=coredns' ="
	@echo "======================================================================="
	@kubectl -n kube-system get deployment,rs,pods -l 'app.kubernetes.io/name=coredns'
