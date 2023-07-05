ODOO_REPLICAS?=1

.PHONY: odoo-deploy
odoo-deploy:
	kubectl apply -f ./app/odoo/namespace.yml
	helmfile --file ./app/odoo/helmfile.yaml apply

.PHONY: odoo-remove
odoo-remove:
	-helmfile --file ./app/odoo/helmfile.yaml destroy
	-kubectl delete -f ./app/odoo/namespace.yml

.PHONY: odoo-debug
odoo-debug:
	kubectl -n erp exec -it `kubectl -n erp get pods -l app.kubernetes.io/instance=odoo -o name | head -n 1` -- bash

.PHONY: odoo-logs
odoo-logs:
	#TODO: update
	kubectl -n erp logs `kubectl -n erp get pods -l app.kubernetes.io/instance=odoo -o name | head -n 1` --follow

.PHONY: odoo-stop
odoo-stop:
	kubectl -n erp scale deployment/odoo --replicas=0

.PHONY: odoo-start
odoo-start:
	kubectl -n erp scale deployment/odoo --replicas=${ODOO_REPLICAS}

.PHONY: odoo-restart
odoo-restart:
	kubectl -n erp rollout restart deployment/odoo

.PHONY: odoo-status
odoo-status:
	@echo "======================================================================================"
	@echo "= odoo Network Resources:                                                            ="
	@echo "=   kubectl -n erp get svc,endpoints,ingress -l app.kubernetes.io/instance=odoo'        ="
	@echo "======================================================================================"
	@kubectl -n erp get svc -l 'app.kubernetes.io/instance=odoo' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n erp get endpoints,ingress -l 'app.kubernetes.io/instance=odoo'
	@echo "\n======================================================================================"
	@echo "= odoo Storage Resources:                                                            ="
	@echo "=   kubectl -n erp get pvc -l 'app.kubernetes.io/instance=odoo'                         ="
	@echo "======================================================================================"
	@kubectl -n erp get pvc -l 'app.kubernetes.io/instance=odoo' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================================"
	@echo "= odoo Deployment Resources:                                                         ="
	@echo "=   kubectl -n erp get deployment,rs,pods -l 'app.kubernetes.io/instance=odoo'          ="
	@echo "======================================================================================"
	@kubectl -n erp get deployment,rs,pods -l 'app.kubernetes.io/instance=odoo'
