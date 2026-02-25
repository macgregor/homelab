GRAFANA_REPLICAS?=1
admin-pass?=${FOUNDRY_INSTANCE_ADMIN_PASS}
foundry-user?=${FOUNDRY_LICENSE_USER}
foundry-pass?=${FOUNDRY_LICENSE_PASS}

.PHONY: grafana-deploy
grafana-deploy:
	kubectl apply -f ./app/grafana/namespace.yml
	kubectl apply -f ./app/grafana/storage.yml
	kubectl apply -f ./app/grafana/network.yml
	kubectl apply -f ./app/grafana/grafana.yml

.PHONY: grafana-remove
grafana-remove:
	-kubectl delete -f ./app/grafana/network.yml
	-kubectl delete -f ./app/grafana/grafana.yml
	-kubectl delete -f ./app/grafana/storage.yml
	-kubectl delete -f ./app/grafana/namespace.yml --cascade=background

.PHONY: grafana-debug
grafana-debug:
	kubectl -n grafana exec -it `kubectl -n grafana get pods -l app.kubernetes.io/name=grafana -o name` -- bash

.PHONY: grafana-logs
grafana-logs:
	kubectl -n grafana logs -l app.kubernetes.io/name=grafana --follow

.PHONY: grafana-stop
grafana-stop:
	kubectl -n grafana scale deployment/grafana --replicas=0

.PHONY: grafana-start
grafana-start:
	kubectl -n grafana scale deployment/grafana --replicas=${GRAFANA_REPLICAS}

.PHONY: grafana-restart
grafana-restart:
	kubectl -n grafana rollout restart deployment/grafana

.PHONY: grafana-status
grafana-status:
	@echo "======================================================================================"
	@echo "= grafana Network Resources:                                                         ="
	@echo "=   kubectl -n grafana get svc,endpoints,ingress -l app.kubernetes.io/name=grafana'  ="
	@echo "======================================================================================"
	@kubectl -n grafana get svc -l 'app.kubernetes.io/name=grafana' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n grafana get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= grafana Storage Resources:                                                         ="
	@echo "=   kubectl -n grafana get pvc -l 'app.kubernetes.io/name=grafana'                   ="
	@echo "======================================================================================"
	@kubectl -n grafana get pvc -l 'app.kubernetes.io/name=grafana' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= grafana Deployment Resources:                                                      ="
	@echo "=   kubectl -n grafana get deployment,rs,pods -l 'app.kubernetes.io/name=grafana'    ="
	@echo "======================================================================================"
	@kubectl -n grafana get deployment,rs,pods -l 'app.kubernetes.io/name=grafana'
