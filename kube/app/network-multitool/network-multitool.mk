NETWORK_MULTITOOL_REPLICAS?=2

.PHONY: network-multitool-deploy
network-multitool-deploy:
	kubectl apply -f ./app/network-multitool/network.yml
	kubectl apply -f ./app/network-multitool/network-multitool.yml

.PHONY: network-multitool-remove
network-multitool-remove:
	-kubectl delete -f ./app/network-multitool/network-multitool.yml
	-kubectl -n kube-system get pvc -l 'app.kubernetes.io/name=network-multitool' -o name | xargs -I{} kubectl -n kube-system delete "{}"
	-kubectl delete -f ./app/network-multitool/network.yml

.PHONY: network-multitool-debug
network-multitool-debug:
	kubectl -n kube-system exec -it `kubectl -n kube-system get pods -l app.kubernetes.io/name=network-multitool -o name | head -n 1` -- bash

.PHONY: network-multitool-logs
network-multitool-logs:
	@echo "TODO"

.PHONY: network-multitool-stop
network-multitool-stop:
	kubectl -n kube-system scale statefulset/network-multitool --replicas=0

.PHONY: network-multitool-start
network-multitool-start:
	kubectl -n kube-system scale statefulset/network-multitool --replicas=${NETWORK_MULTITOOL_REPLICAS}

.PHONY: network-multitool-restart
network-multitool-restart:
	kubectl -n kube-system rollout restart statefulset/network-multitool

.PHONY: network-multitool-status
network-multitool-status:
	@echo "======================================================================="
	@echo "= network-multitool Network Resources:                                ="
	@echo "=   kubectl -n kube-system get svc,endpoints,ingress -l app.kubernetes.io/name=network-multitool' ="
	@echo "======================================================================="
	@kubectl -n kube-system get svc -l 'app.kubernetes.io/name=network-multitool' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n kube-system get endpoints,ingress
	@echo -e "\n======================================================================="
	@echo "= network-multitool Storage Resources:                                ="
	@echo "=   kubectl -n kube-system get pvc -l 'app=network-multitool'         ="
	@echo "======================================================================="
	@kubectl -n kube-system-multitool get pvc -l 'app.kubernetes.io/name=network-multitool' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= network-multitool Deployment Resources:                             ="
	@echo "=   kubectl -n kube-system get deployment,rs,pods -l 'app.kubernetes.io/name=network-multitool' ="
	@echo "======================================================================="
	@kubectl -n kube-system get deployment,rs,pods -l 'app.kubernetes.io/name=network-multitool'
