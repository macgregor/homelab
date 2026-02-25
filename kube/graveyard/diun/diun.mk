DIUN_REPLICAS?=1

.PHONY: diun-deploy
diun-deploy:
	kubectl apply -f ./observation/diun/namespace.yml
	kubectl apply -f ./observation/diun/rbac.yml
	kubectl apply -f ./observation/diun/storage.yml
	@kubectl create secret generic registry-credentials \
		-n observation \
		--save-config \
		--dry-run=client \
		--from-literal=DIUN_REGOPTS_0_NAME="docker.io" \
		--from-literal=DIUN_REGOPTS_0_SELECTOR="image" \
		--from-literal=DIUN_REGOPTS_0_USERNAME="${DOCKER_USERNAME}" \
		--from-literal=DIUN_REGOPTS_0_PASSWORD="${DOCKER_TOKEN}" \
		--from-literal=DIUN_REGOPTS_1_NAME="ghcr.io" \
		--from-literal=DIUN_REGOPTS_1_SELECTOR="name" \
		--from-literal=DIUN_REGOPTS_1_USERNAME="${GITHUB_USERNAME}" \
		--from-literal=DIUN_REGOPTS_1_PASSWORD="${GITHUB_TOKEN}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./observation/diun/diun.yml

.PHONY: diun-remove
diun-remove:
	-kubectl delete -f ./observation/diun/diun.yml
	-kubectl delete -f ./observation/diun/rbac.yml
	-kubectl delete -f ./observation/diun/storage.yml
	-kubectl -n observation delete secret/registry-credentials

.PHONY: diun-debug
diun-debug:
	kubectl -n observation exec -it `kubectl -n observation get pods -l app.kubernetes.io/name=diun -o name` -- /bin/sh

.PHONY: diun-notification-test
diun-notification-test:
	kubectl -n observation exec -it `kubectl -n observation get pods -l app.kubernetes.io/name=diun -o name` -- diun notif test

.PHONY: diun-logs
diun-logs:
	kubectl -n observation logs -l app.kubernetes.io/name=diun --follow

.PHONY: diun-stop
diun-stop:
	kubectl -n observation scale deployment/diun --replicas=0

.PHONY: diun-start
diun-start:
	kubectl -n observation scale deployment/diun --replicas=${DIUN_REPLICAS}

.PHONY: diun-restart
diun-restart:
	kubectl -n observation rollout restart deployment/diun

.PHONY: diun-status
diun-status:
	@echo "======================================================================================"
	@echo "= diun Network Resources:                                                            ="
	@echo "=   kubectl -n observation get svc,endpoints,ingress -l app.kubernetes.io/name=diun' ="
	@echo "======================================================================================"
	@kubectl -n observation get svc -l 'app.kubernetes.io/name=diun' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n observation get endpoints,ingress
	@echo -e "\n======================================================================================"
	@echo "= diun Storage Resources:                                                            ="
	@echo "=   kubectl -n observation get pvc -l 'app.kubernetes.io/name=diun'                  ="
	@echo "======================================================================================"
	@kubectl -n observation get pvc -l 'app.kubernetes.io/name=diun' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================================"
	@echo "= diun Deployment Resources:                                                         ="
	@echo "=   kubectl -n observation get deployment,rs,pods -l 'app.kubernetes.io/name=diun'   ="
	@echo "======================================================================================"
	@kubectl -n observation get deployment,rs,pods -l 'app.kubernetes.io/name=diun'
