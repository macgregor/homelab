.PHONY: prometheus-status
prometheus-status:
	@echo "============================================================================================"
	@echo "= prometheus Network Resources:                                                            ="
	@echo "=   kubectl -n obs get svc,endpoints,ingress -l app.kubernetes.io/name=prometheus'  ="
	@echo "============================================================================================"
	@kubectl -n obs get svc -l 'app.kubernetes.io/name=prometheus' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n obs get endpoints,ingress
	@echo "\n============================================================================================"
	@echo "= prometheus Storage Resources:                                                            ="
	@echo "=   kubectl -n obs get pvc -l 'app.kubernetes.io/name=prometheus'                   ="
	@echo "============================================================================================"
	@kubectl -n obs get pvc -l 'app.kubernetes.io/name=prometheus' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n============================================================================================"
	@echo "= prometheus Deployment Resources:                                                         ="
	@echo "=   kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=prometheus'    ="
	@echo "============================================================================================"
	@kubectl -n obs get deployment,rs,pods -l 'app.kubernetes.io/name=prometheus'
