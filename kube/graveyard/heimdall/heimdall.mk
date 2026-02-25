HEIMDALL_REPLICAS?=1

.PHONY: heimdall-deploy
heimdall-deploy:
	kubectl apply -f ./app/heimdall/namespace.yml
	kubectl apply -f ./app/heimdall/storage.yml
	helmfile --file ./app/heimdall/helmfile.yaml apply

.PHONY: heimdall-remove
heimdall-remove:
	-helmfile --file ./app/heimdall/helmfile.yaml destroy
	-kubectl delete -f ./app/heimdall/storage.yml

.PHONY: heimdall-debug
heimdall-debug:
	kubectl -n dashboards exec -it `kubectl -n dashboards get pods -l app.kubernetes.io/name=heimdall -o name | head -n 1` -- bash

.PHONY: heimdall-logs
heimdall-logs:
	#TODO: update
	kubectl -n dashboards logs `kubectl -n dashboards get pods -l app.kubernetes.io/name=heimdall -o name | head -n 1` --follow

.PHONY: heimdall-stop
heimdall-stop:
	kubectl -n dashboards scale deployment/heimdall --replicas=0

.PHONY: heimdall-start
heimdall-start:
	kubectl -n dashboards scale deployment/heimdall --replicas=${HEIMDALL_REPLICAS}

.PHONY: heimdall-restart
heimdall-restart:
	kubectl -n dashboards rollout restart deployment/heimdall

.PHONY: heimdall-status
heimdall-status:
	@echo "======================================================================================"
	@echo "= heimdall Network Resources:                                                        ="
	@echo "=   kubectl -n dashboards get svc,endpoints,ingress -l app.kubernetes.io/name=heimdall' ="
	@echo "======================================================================================"
	@kubectl -n dashboards get svc -l 'app.kubernetes.io/name=heimdall' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n dashboards get endpoints,ingress -l 'app.kubernetes.io/name=heimdall'
	@echo -e "\n======================================================================================"
	@echo "= heimdall Storage Resources:                                                        ="
	@echo "=   kubectl -n dashboards get pvc -l 'app.kubernetes.io/name=heimdall'               ="
	@echo "======================================================================================"
	@kubectl -n dashboards get pvc -l 'app.kubernetes.io/name=heimdall' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= heimdall Deployment Resources:                                                     ="
	@echo "=   kubectl -n dashboards get deployment,rs,pods -l 'app.kubernetes.io/name=heimdall' ="
	@echo "======================================================================================"
	@kubectl -n dashboards get deployment,rs,pods -l 'app.kubernetes.io/name=heimdall'
