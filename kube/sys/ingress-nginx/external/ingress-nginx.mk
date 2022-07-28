INGRESS_EXTERNAL_REPLICAS?=1

.PHONY: ingress-external-deploy
ingress-external-deploy:
	helmfile --file ./sys/ingress-nginx/external/helmfile.yaml apply

.PHONY: ingress-external-remove
ingress-external-remove:
	helmfile --file ./sys/ingress-nginx/external/helmfile.yaml destroy

.PHONY: ingress-external-debug
ingress-external-debug:
	kubectl -n ingress-nginx exec -it `kubectl -n ingress-nginx get pods -l app.kubernetes.io/instance=ingress-nginx-external -o name | head -n 1` -- bash

.PHONY: ingress-external-logs
ingress-external-logs:
	kubectl -n ingress-nginx logs `kubectl -n ingress-nginx get pods -l app.kubernetes.io/instance=ingress-nginx-external -o name | head -n 1` --follow

.PHONY: ingress-external-stop
ingress-external-stop:
	kubectl -n ingress-nginx scale deployment/ingress-nginx-external-controller-external --replicas=0

.PHONY: ingress-external-start
ingress-external-start:
	kubectl -n ingress-nginx scale deployment/ingress-nginx-external-controller-external --replicas=${INGRESS_EXTERNAL_REPLICAS}

.PHONY: ingress-external-restart
ingress-external-restart:
	kubectl -n ingress-nginx rollout restart deployment/ingress-nginx-external-controller-external

.PHONY: ingress-external-status
ingress-external-status:
	@echo "======================================================================================"
	@echo "= ingress-external Network Resources:                                                            ="
	@echo "=   kubectl -n ingress-nginx get svc,endpoints,ingress -l app.kubernetes.io/instance=ingress-nginx-external'        ="
	@echo "======================================================================================"
	@kubectl -n ingress-nginx get svc -l 'app.kubernetes.io/instance=ingress-nginx-external' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n ingress-nginx get endpoints,ingress -l 'app.kubernetes.io/instance=ingress-nginx-external'
	@echo "\n======================================================================================"
	@echo "= ingress-external Storage Resources:                                                            ="
	@echo "=   kubectl -n ingress-nginx get pvc -l 'app.kubernetes.io/instance=ingress-nginx-external'                         ="
	@echo "======================================================================================"
	@kubectl -n ingress-nginx get pvc -l 'app.kubernetes.io/instance=ingress-nginx-external' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= ingress-external Deployment Resources:                                                         ="
	@echo "=   kubectl -n ingress-nginx get deployment,rs,pods -l 'app.kubernetes.io/instance=ingress-nginx-external'          ="
	@echo "======================================================================================"
	@kubectl -n ingress-nginx get deployment,rs,pods -l 'app.kubernetes.io/instance=ingress-nginx-external'
