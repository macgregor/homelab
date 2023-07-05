NTFY_REPLICAS?=1

.PHONY: ntfy-deploy
ntfy-deploy:
	kubectl apply -f ./app/ntfy/namespace.yml
	kubectl apply -f ./app/ntfy/storage.yml
	kubectl apply -f ./app/ntfy/network.yml
	kubectl apply -f ./app/ntfy/ntfy.yml

.PHONY: ntfy-remove
ntfy-remove:
	-kubectl delete -f ./app/ntfy/network.yml
	-kubectl delete -f ./app/ntfy/ntfy.yml
	-kubectl delete -f ./app/ntfy/storage.yml
	-kubectl delete -f ./app/ntfy/namespace.yml

.PHONY: ntfy-debug
ntfy-debug:
	kubectl -n ntfy exec -it `kubectl -n ntfy get pods -l app.kubernetes.io/name=ntfy -o name` -- /bin/sh

.PHONY: ntfy-logs
ntfy-logs:
	kubectl -n ntfy logs -l app.kubernetes.io/name=ntfy --follow

.PHONY: ntfy-stop
ntfy-stop:
	kubectl -n ntfy scale deployment/ntfy --replicas=0

.PHONY: ntfy-start
ntfy-start:
	kubectl -n ntfy scale deployment/ntfy --replicas=${NTFY_REPLICAS}

.PHONY: ntfy-restart
ntfy-restart:
	kubectl -n ntfy rollout restart deployment/ntfy

.PHONY: ntfy-status
ntfy-status:
	@echo "======================================================================================"
	@echo "= ntfy Network Resources:                                                            ="
	@echo "=   kubectl -n ntfy get svc,endpoints,ingress -l app.kubernetes.io/name=ntfy'        ="
	@echo "======================================================================================"
	@kubectl -n ntfy get svc -l 'app.kubernetes.io/name=ntfy' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n ntfy get endpoints,ingress -l 'app.kubernetes.io/name=ntfy'
	@echo "\n======================================================================================"
	@echo "= ntfy Storage Resources:                                                            ="
	@echo "=   kubectl -n ntfy get pvc -l 'app.kubernetes.io/name=ntfy'                         ="
	@echo "======================================================================================"
	@kubectl -n ntfy get pvc -l 'app.kubernetes.io/name=ntfy' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= ntfy Deployment Resources:                                                         ="
	@echo "=   kubectl -n ntfy get deployment,rs,pods -l 'app.kubernetes.io/name=ntfy'          ="
	@echo "======================================================================================"
	@kubectl -n ntfy get deployment,rs,pods -l 'app.kubernetes.io/name=ntfy'
