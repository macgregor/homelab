PROMETHEUS_OPERATOR_REPLICAS?=1

.PHONY: prometheus-debug
prometheus-debug:
	kubectl -n obs exec -it `kubectl -n obs get pods -l app.kubernetes.io/name=prometheus -o name` -- bash

.PHONY: prometheus-logs
prometheus-logs:
	kubectl -n obs logs `kubectl -n obs get pods -l app.kubernetes.io/name=prometheus -o name` --follow

.PHONY: prometheus-stop
prometheus-stop:
	kubectl -n obs scale deployment.apps/kps-kube-prometheus-stack-operator --replicas=0
	kubectl -n obs scale statefulset.apps/prometheus-kps-kube-prometheus-stack-prometheus --replicas=0

.PHONY: prometheus-start
prometheus-start:
	kubectl -n obs scale deployment.apps/kps-kube-prometheus-stack-operator --replicas=${PROMETHEUS_OPERATOR_REPLICAS}

.PHONY: prometheus-restart
prometheus-restart:
	kubectl -n obs rollout restart statefulset.apps/prometheus-kps-kube-prometheus-stack-prometheus

.PHONY: prometheus-status
prometheus-status:
	@echo "======================================================================================"
	@echo "= prometheus Network Resources:                                                            ="
	@echo "=   kubectl -n obs get svc,endpoints,ingress -l app.kubernetes.io/name=prometheus'        ="
	@echo "======================================================================================"
	@kubectl -n obs get svc -l 'app.kubernetes.io/name=prometheus' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n obs get endpoints,ingress -l 'app.kubernetes.io/name=prometheus'
	@echo "\n======================================================================================"
	@echo "= prometheus Storage Resources:                                                            ="
	@echo "=   kubectl -n obs get pvc -l 'app.kubernetes.io/name=prometheus'                         ="
	@echo "======================================================================================"
	@kubectl -n obs get pvc -l 'app.kubernetes.io/name=prometheus' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= prometheus Deployment Resources:                                                         ="
	@echo "=   kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=prometheus'          ="
	@echo "======================================================================================"
	@kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=prometheus'
