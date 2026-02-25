KUBERNETES_DASHBOARD_REPLICAS?=1

.PHONY: kubernetes-dashboard-deploy
kubernetes-dashboard-deploy:
	kubectl apply -f ./app/kubernetes-dashboard/namespace.yml
	kubectl apply -f ./app/kubernetes-dashboard/base.yml
	kubectl apply -f ./app/kubernetes-dashboard/deployment.yml
	kubectl apply -f ./app/kubernetes-dashboard/network.yml

.PHONY: kubernetes-dashboard-remove
kubernetes-dashboard-remove:
	-kubectl delete -f ./app/kubernetes-dashboard/network.yml
	-kubectl delete -f ./app/kubernetes-dashboard/deployment.yml
	-kubectl delete -f ./app/kubernetes-dashboard/base.yml
	-kubectl delete -f ./app/kubernetes-dashboard/namespace.yml

.PHONY: kubernetes-dashboard-debug
kubernetes-dashboard-debug:
	kubectl -n kubernetes-dashboard exec -it `kubectl -n kubernetes-dashboard get pods -l app.kubernetes.io/name=kubernetes-dashboard -o name | head -n 1` -- bash

.PHONY: kubernetes-dashboard-logs
kubernetes-dashboard-logs:
	#TODO: update
	kubectl -n kubernetes-dashboard logs `kubectl -n kubernetes-dashboard get pods -l app.kubernetes.io/name=kubernetes-dashboard -o name | head -n 1` --follow

.PHONY: kubernetes-dashboard-stop
kubernetes-dashboard-stop:
	kubectl -n kubernetes-dashboard scale deployment/kubernetes-dashboard --replicas=0

.PHONY: kubernetes-dashboard-start
kubernetes-dashboard-start:
	kubectl -n kubernetes-dashboard scale deployment/kubernetes-dashboard --replicas=${KUBERNETES_DASHBOARD_REPLICAS}

.PHONY: kubernetes-dashboard-restart
kubernetes-dashboard-restart:
	kubectl -n kubernetes-dashboard rollout restart deployment/kubernetes-dashboard

.PHONY: kubernetes-dashboard-status
kubernetes-dashboard-status:
	@echo "======================================================================================"
	@echo "= kubernetes-dashboard Network Resources:                                            ="
	@echo "=   kubectl -n kubernetes-dashboard get svc,endpoints,ingress -l app.kubernetes.io/name=kubernetes-dashboard' ="
	@echo "======================================================================================"
	@kubectl -n kubernetes-dashboard get svc -l 'app.kubernetes.io/name=kubernetes-dashboard' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n kubernetes-dashboard get endpoints,ingress -l 'app.kubernetes.io/name=kubernetes-dashboard'
	@echo -e "\n======================================================================================"
	@echo "= kubernetes-dashboard Storage Resources:                                            ="
	@echo "=   kubectl -n kubernetes-dashboard get pvc -l 'app.kubernetes.io/name=kubernetes-dashboard' ="
	@echo "======================================================================================"
	@kubectl -n kubernetes-dashboard get pvc -l 'app.kubernetes.io/name=kubernetes-dashboard' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= kubernetes-dashboard Deployment Resources:                                         ="
	@echo "=   kubectl -n kubernetes-dashboard get deployment,rs,pods -l 'app.kubernetes.io/name=kubernetes-dashboard' ="
	@echo "======================================================================================"
	@kubectl -n kubernetes-dashboard get deployment,rs,pods -l 'app.kubernetes.io/name=kubernetes-dashboard'
