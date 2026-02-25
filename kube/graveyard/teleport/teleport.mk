TELEPORT_REPLICAS?=1
TELEPORT_POD_NAME?=`kubectl -n teleport get pod -l app=teleport-cluster -o jsonpath='{.items[0].metadata.name}'`


.PHONY: teleport-deploy
teleport-deploy:
	kubectl apply -f ./app/teleport/namespace.yml
	kubectl apply -f ./app/teleport/storage.yml
	kubectl apply -f ./app/teleport/network.yml
	helmfile --file ./app/teleport/helmfile.yaml apply

.PHONY: teleport-remove
teleport-remove:
	-kubectl delete -f ./app/teleport/network.yml
	-helmfile --file ./app/teleport/helmfile.yaml destroy
	-kubectl delete -f ./app/teleport/storage.yml
	-kubectl apply -f ./app/teleport/namespace.yml --cascade=background

.PHONY: teleport-debug
teleport-debug:
	kubectl -n teleport exec -it `kubectl -n teleport get pods -l app=teleport-cluster -o name` -- bash

.PHONY: teleport-logs
teleport-logs:
	#TODO: update
	kubectl -n teleport logs `kubectl -n teleport get pods -l app=teleport-cluster -o name` --follow

.PHONY: teleport-stop
teleport-stop:
	kubectl -n teleport scale deployment/teleport-cluster --replicas=0

.PHONY: teleport-start
teleport-start:
	kubectl -n teleport scale deployment/teleport-cluster --replicas=${TELEPORT_REPLICAS}

.PHONY: teleport-restart
teleport-restart:
	kubectl -n teleport rollout restart deployment/teleport-cluster

.PHONY: teleport-status
teleport-status:
	@echo "======================================================================="
	@echo "= teleport Network Resources:                                         ="
	@echo "=   kubectl -n teleport get svc,endpoints,ingress -l 'app=teleport-cluster' ="
	@echo "======================================================================="
	@kubectl -n teleport get svc -l 'app=teleport-cluster' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n teleport get endpoints,ingress -l 'app=teleport-cluster'
	@echo -e "\n======================================================================="
	@echo "= teleport Storage Resources:                                         ="
	@echo "=   kubectl -n teleport get pvc -l 'app=teleport-cluster'             ="
	@echo "======================================================================="
	@kubectl -n teleport get pvc -l 'app=teleport-cluster' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= teleport Deployment Resources:                                      ="
	@echo "=   kubectl -n teleport get deployment,rs,pods -l 'app=teleport-cluster' ="
	@echo "======================================================================="
	@kubectl -n teleport get deployment,rs,pods -l 'app=teleport-cluster'

.PHONY: teleport-cert
teleport-cert:
	kubectl -n teleport get secret/teleport-tls -o json | jq '.data["tls.crt"]' -r | base64 -d | openssl x509 -noout -text

.PHONY: teleport-lb-test
teleport-lb-test:
	curl -kvL --resolve 'teleport.matthew-stratton.me:443:192.168.1.220' https://teleport.matthew-stratton.me/

.PHONY: teleport-audit-log
teleport-audit-log:
	kubectl exec -ti "${TELEPORT_POD_NAME}" -- tail -n 100 /var/lib/teleport/log/events.log

.PHONY: teleport-pod-create
teleport-auth-initial-user:
	kubectl exec -i ${TELEPORT_POD_NAME} -n teleport -- tctl create -f < ./app/teleport/auth/admin_role.yml
	kubectl exec -ti ${TELEPORT_POD_NAME} -n teleport -- tctl  users add ${TELEPORT_KUBE_LOCAL_USER} --roles=admin