
.PHONY: synology-dsm-deploy
synology-dsm-deploy:
	kubectl apply -f ./app/synology-dsm/namespace.yml
	kubectl apply -f ./app/synology-dsm/network.yml

.PHONY: synology-dsm-remove
synology-dsm-remove:
	-kubectl delete -f ./app/synology-dsm/network.yml
	-kubectl apply -f ./app/synology-dsm/namespace.yml --cascade=background

.PHONY: synology-dsm-status
synology-dsm-status:
	@echo "======================================================================="
	@echo "= synology-dsm Network Resources:                                         ="
	@echo "=   kubectl -n synology-dsm get svc,endpoints,ingress -l app=synology-dsm'    ="
	@echo "======================================================================="
	@kubectl -n synology-dsm get svc -l 'app=synology-dsm' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n synology-dsm get endpoints,ingress
	@echo "\n======================================================================="
	@echo "= synology-dsm Storage Resources:                                          ="
	@echo "=   kubectl -n synology-dsm get pvc -l 'app=synology-dsm'                      ="
	@echo "======================================================================="
	@kubectl -n synology-dsm get pvc -l 'app=synology-dsm' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================="
	@echo "= synology-dsm Deployment Resources:                                       ="
	@echo "=   kubectl -n synology-dsm get deployment,rs,pods -l 'app=synology-dsm'       ="
	@echo "======================================================================="
	@kubectl -n synology-dsm get deployment,rs,pods -l 'app=synology-dsm'
