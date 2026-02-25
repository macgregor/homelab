OAUTH2_PROXY_REPLICAS?=1

.PHONY: oauth2-proxy-deploy
oauth2-proxy-deploy:
	helmfile --file ./sys/oauth2-proxy/helmfile.yaml apply

.PHONY: oauth2-proxy-remove
oauth2-proxy-remove:
	helmfile --file ./sys/oauth2-proxy/helmfile.yaml destroy

.PHONY: oauth2-proxy-logs
oauth2-proxy-logs:
	kubectl -n oauth2-proxy logs -l app.kubernetes.io/name=oauth2-proxy --follow

.PHONY: oauth2-proxy-stop
oauth2-proxy-stop:
	kubectl -n oauth2-proxy scale deployment/oauth2-proxy --replicas=0

.PHONY: oauth2-proxy-start
oauth2-proxy-start:
	kubectl -n oauth2-proxy scale deployment/oauth2-proxy --replicas=${OAUTH2_PROXY_REPLICAS}

.PHONY: oauth2-proxy-restart
oauth2-proxy-restart:
	kubectl -n oauth2-proxy rollout restart deployment/oauth2-proxy

.PHONY: oauth2-proxy-status
oauth2-proxy-status:
	@echo "======================================================================="
	@echo "= oauth2-proxy Network Resources:                                     ="
	@echo "=   kubectl -n oauth2-proxy get svc,endpoints,ingress -l app.kubernetes.io/name=oauth2-proxy' ="
	@echo "======================================================================="
	@kubectl -n oauth2-proxy get svc -l 'app.kubernetes.io/name=oauth2-proxy' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n oauth2-proxy get endpoints,ingress -l 'app.kubernetes.io/name=oauth2-proxy'
	@echo -e "\n======================================================================="
	@echo "= oauth2-proxy Storage Resources:                                     ="
	@echo "=   kubectl -n oauth2-proxy get pvc -l 'app.kubernetes.io/name=oauth2-proxy' ="
	@echo "======================================================================="
	@kubectl -n oauth2-proxy get pvc -l 'app.kubernetes.io/name=oauth2-proxy' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= oauth2-proxy Deployment Resources:                                  ="
	@echo "=   kubectl -n oauth2-proxy get deployment,rs,pods -l 'app.kubernetes.io/name=oauth2-proxy' ="
	@echo "======================================================================="
	@kubectl -n oauth2-proxy get deployment,rs,pods -l 'app.kubernetes.io/name=oauth2-proxy'
