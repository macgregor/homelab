GRAFANA_REPLICAS?=1

.PHONY: grafana-debug
grafana-debug:
	kubectl -n obs exec -it `kubectl -n obs get pods -l app.kubernetes.io/name=grafana -o name` -- bash

.PHONY: grafana-logs
grafana-logs:
	kubectl -n obs logs `kubectl -n obs get pods -l app.kubernetes.io/name=grafana -o name` -c grafana --follow

.PHONY: grafana-stop
grafana-stop:
	kubectl -n obs scale deployment/kps-grafana --replicas=0

.PHONY: grafana-start
grafana-start:
	kubectl -n obs scale deployment/kps-grafana --replicas=${GRAFANA_REPLICAS}

.PHONY: grafana-restart
grafana-restart:
	kubectl -n obs rollout restart deployment/kps-grafana

.PHONY: grafana-status
grafana-status:
	@echo "======================================================================================"
	@echo "= grafana Network Resources:                                                         ="
	@echo "=   kubectl -n obs get svc,endpoints,ingress -l app.kubernetes.io/name=grafana'      ="
	@echo "======================================================================================"
	@kubectl -n obs get svc -l 'app.kubernetes.io/name=grafana' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n obs get endpoints,ingress -l 'app.kubernetes.io/name=grafana'
	@echo -e "\n======================================================================================"
	@echo "= grafana Storage Resources:                                                         ="
	@echo "=   kubectl -n obs get pvc -l 'app.kubernetes.io/name=grafana'                       ="
	@echo "======================================================================================"
	@kubectl -n obs get pvc -l 'app.kubernetes.io/name=grafana' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= grafana Deployment Resources:                                                      ="
	@echo "=   kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=grafana'        ="
	@echo "======================================================================================"
	@kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=grafana'
