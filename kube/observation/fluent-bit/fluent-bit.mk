FLUENT_BIT_REPLICAS?=2

.PHONY: fluent-bit-deploy
fluent-bit-deploy:
	helmfile --file ./observation/fluent-bit/helmfile.yaml apply

.PHONY: fluent-bit-remove
fluent-bit-remove:
	helmfile --file ./observation/fluent-bit/helmfile.yaml destroy

.PHONY: fluent-bit-stop
fluent-bit-stop:
	kubectl -n obs scale daemonset/fluent-bit --replicas=0

.PHONY: fluent-bit-start
fluent-bit-start:
	kubectl -n obs scale daemonset/fluent-bit --replicas=${FLUENT_BIT_REPLICAS}

.PHONY: fluent-bit-restart
fluent-bit-restart:
	kubectl -n obs rollout restart daemonset/fluent-bit

.PHONY: fluent-bit-status
fluent-bit-status:
	@echo "============================================================================================"
	@echo "= fluent-bit Network Resources:                                                            ="
	@echo "=   kubectl -n obs get svc,endpoints,ingress -l app.kubernetes.io/name=fluent-bit'         ="
	@echo "============================================================================================"
	@kubectl -n obs get svc -l 'app.kubernetes.io/name=fluent-bit' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n obs get endpoints,ingress
	@echo -e "\n============================================================================================"
	@echo "= fluent-bit Storage Resources:                                                            ="
	@echo "=   kubectl -n obs get pvc -l 'app.kubernetes.io/name=fluent-bit'                          ="
	@echo "============================================================================================"
	@kubectl -n obs get pvc -l 'app.kubernetes.io/name=fluent-bit' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n============================================================================================"
	@echo "= fluent-bit Deployment Resources:                                                         ="
	@echo "=   kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=fluent-bit'           ="
	@echo "============================================================================================"
	@kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=fluent-bit'
