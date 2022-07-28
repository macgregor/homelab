INGRESS_INTERNAL_REPLICAS?=1

.PHONY: ingress-internal-deploy
ingress-internal-deploy:
	helmfile --file ./sys/ingress-nginx/internal/helmfile.yaml apply

.PHONY: ingress-internal-remove
ingress-internal-remove:
	helmfile --file ./sys/ingress-nginx/internal/helmfile.yaml destroy

.PHONY: ingress-internal-debug
ingress-internal-debug:
	kubectl -n ingress-nginx exec -it `kubectl -n ingress-nginx get pods -l app.kubernetes.io/instance=ingress-nginx-internal -o name | head -n 1` -- bash

.PHONY: ingress-internal-logs
ingress-internal-logs:
	kubectl -n ingress-nginx logs `kubectl -n ingress-nginx get pods -l app.kubernetes.io/instance=ingress-nginx-internal -o name | head -n 1` --follow

.PHONY: ingress-internal-stop
ingress-internal-stop:
	kubectl -n ingress-nginx scale deployment/ingress-nginx-internal-controller-internal --replicas=0

.PHONY: ingress-internal-start
ingress-internal-start:
	kubectl -n ingress-nginx scale deployment/ingress-nginx-internal-controller-internal --replicas=${INGRESS_INTERNAL_REPLICAS}

.PHONY: ingress-internal-restart
ingress-internal-restart:
	kubectl -n ingress-nginx rollout restart deployment/ingress-nginx-internal-controller-internal

.PHONY: ingress-internal-status
ingress-internal-status:
	@echo "======================================================================================"
	@echo "= ingress-internal Network Resources:                                                            ="
	@echo "=   kubectl -n ingress-nginx get svc,endpoints,ingress -l app.kubernetes.io/instance=ingress-nginx-internal'        ="
	@echo "======================================================================================"
	@kubectl -n ingress-nginx get svc -l 'app.kubernetes.io/instance=ingress-nginx-internal' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n ingress-nginx get endpoints,ingress -l 'app.kubernetes.io/instance=ingress-nginx-internal'
	@echo "\n======================================================================================"
	@echo "= ingress-internal Storage Resources:                                                            ="
	@echo "=   kubectl -n ingress-nginx get pvc -l 'app.kubernetes.io/instance=ingress-nginx-internal'                         ="
	@echo "======================================================================================"
	@kubectl -n ingress-nginx get pvc -l 'app.kubernetes.io/instance=ingress-nginx-internal' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= ingress-internal Deployment Resources:                                                         ="
	@echo "=   kubectl -n ingress-nginx get deployment,rs,pods -l 'app.kubernetes.io/instance=ingress-nginx-internal'          ="
	@echo "======================================================================================"
	@kubectl -n ingress-nginx get deployment,rs,pods -l 'app.kubernetes.io/instance=ingress-nginx-internal'
