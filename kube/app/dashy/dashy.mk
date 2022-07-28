DASHY_REPLICAS?=1

.PHONY: dashy-deploy
dashy-deploy:
	kubectl apply -f ./app/dashy/namespace.yml
	kubectl apply -f ./app/dashy/storage.yml
	kubectl apply -f ./app/dashy/network.yml
	kubectl apply -f ./app/dashy/dashy.yml

.PHONY: dashy-remove
dashy-remove:
	-kubectl delete -f ./app/dashy/network.yml
	-kubectl delete -f ./app/dashy/dashy.yml
	-kubectl delete -f ./app/dashy/storage.yml

.PHONY: dashy-debug
dashy-debug:
	kubectl -n dashboards exec -it `kubectl -n dashboards get pods -l app.kubernetes.io/name=dashy -o name` -- bash

.PHONY: dashy-logs
dashy-logs:
	kubectl -n dashboards logs -l app.kubernetes.io/name=dashy --follow

.PHONY: dashy-stop
dashy-stop:
	kubectl -n dashboards scale deployment/dashy --replicas=0

.PHONY: dashy-start
dashy-start:
	kubectl -n dashboards scale deployment/dashy --replicas=${DASHY_REPLICAS}

.PHONY: dashy-restart
dashy-restart:
	kubectl -n dashboards rollout restart deployment/dashy

.PHONY: dashy-status
dashy-status:
	@echo "======================================================================================"
	@echo "= dashy Network Resources:                                                            ="
	@echo "=   kubectl -n dashboards get svc,endpoints,ingress -l app.kubernetes.io/name=dashy'        ="
	@echo "======================================================================================"
	@kubectl -n dashboards get svc -l 'app.kubernetes.io/name=dashy' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n dashboards get endpoints,ingress -l 'app.kubernetes.io/name=dashy'
	@echo "\n======================================================================================"
	@echo "= dashy Storage Resources:                                                            ="
	@echo "=   kubectl -n dashboards get pvc -l 'app.kubernetes.io/name=dashy'                         ="
	@echo "======================================================================================"
	@kubectl -n dashboards get pvc -l 'app.kubernetes.io/name=dashy' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= dashy Deployment Resources:                                                         ="
	@echo "=   kubectl -n dashboards get deployment,rs,pods -l 'app.kubernetes.io/name=dashy'          ="
	@echo "======================================================================================"
	@kubectl -n dashboards get deployment,rs,pods -l 'app.kubernetes.io/name=dashy'
