
.PHONY: loki-deploy
loki-deploy:
	kubectl apply -f ./sys/loki/namespace.yml
	kubectl apply -f ./sys/loki/storage.yml
	helmfile --file ./sys/loki/helmfile.yaml apply

.PHONY: loki-remove
loki-remove:
	-helmfile --file ./sys/loki/helmfile.yaml destroy
	-kubectl delete -f ./sys/loki/storage.yml

.PHONY: loki-status
loki-status:
	@echo "======================================================================================"
	@echo "= loki Network Resources:                                                            ="
	@echo "=   kubectl -n obs get svc,endpoints,ingress -l app.kubernetes.io/name=loki'        ="
	@echo "======================================================================================"
	@kubectl -n obs get svc -l 'app.kubernetes.io/name=loki' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n obs get endpoints,ingress
	@echo "\n======================================================================================"
	@echo "= loki Storage Resources:                                                            ="
	@echo "=   kubectl -n obs get pvc -l 'app.kubernetes.io/name=loki'                         ="
	@echo "======================================================================================"
	@kubectl -n obs get pvc -l 'app.kubernetes.io/name=loki' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= loki Deployment Resources:                                                         ="
	@echo "=   kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=loki'          ="
	@echo "======================================================================================"
	@kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=loki'
