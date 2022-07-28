ADGUARD_REPLICAS?=1

.PHONY: adguard-deploy
adguard-deploy:
	kubectl apply -f ./app/adguard/namespace.yml
	kubectl apply -f ./app/adguard/storage.yml
	kubectl apply -f ./app/adguard/network.yml
	helmfile --file ./app/adguard/helmfile.yaml apply

.PHONY: adguard-remove
adguard-remove:
	-kubectl apply -f ./app/adguard/network.yml
	-helmfile --file ./app/adguard/helmfile.yaml destroy
	-kubectl delete -f ./app/adguard/storage.yml

.PHONY: adguard-debug
adguard-debug:
	kubectl -n adguard exec -it `kubectl -n adguard get pods -l app.kubernetes.io/name=adguard-home -o name | head -n 1` -- bash

.PHONY: adguard-logs
adguard-logs:
	#TODO: update
	kubectl -n adguard logs `kubectl -n adguard get pods -l app.kubernetes.io/name=adguard-home -o name | head -n 1` --follow

.PHONY: adguard-stop
adguard-stop:
	kubectl -n adguard scale deployment/adguard-home --replicas=0

.PHONY: adguard-start
adguard-start:
	kubectl -n adguard scale deployment/adguard-home --replicas=${ADGUARD_REPLICAS}

.PHONY: adguard-restart
adguard-restart:
	kubectl -n adguard rollout restart deployment/adguard-home

.PHONY: adguard-status
adguard-status:
	@echo "======================================================================================"
	@echo "= adguard Network Resources:                                                            ="
	@echo "=   kubectl -n adguard get svc,endpoints,ingress -l app.kubernetes.io/name=adguard-home'        ="
	@echo "======================================================================================"
	@kubectl -n adguard get svc -l 'app.kubernetes.io/name=adguard-home' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n adguard get endpoints,ingress -l 'app.kubernetes.io/name=adguard-home'
	@echo "\n======================================================================================"
	@echo "= adguard Storage Resources:                                                            ="
	@echo "=   kubectl -n adguard get pvc -l 'app.kubernetes.io/name=adguard-home'                         ="
	@echo "======================================================================================"
	@kubectl -n adguard get pvc -l 'app.kubernetes.io/name=adguard-home' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= adguard Deployment Resources:                                                         ="
	@echo "=   kubectl -n adguard get deployment,rs,pods -l 'app.kubernetes.io/name=adguard-home'          ="
	@echo "======================================================================================"
	@kubectl -n adguard get deployment,rs,pods -l 'app.kubernetes.io/name=adguard-home'
