MEALIE_REPLICAS?=1

.PHONY: mealie-deploy
mealie-deploy:
	kubectl apply -f ./app/mealie/namespace.yml
	kubectl create secret generic mealie-env \
		-n mealie \
		--save-config \
		--dry-run=client \
		--from-literal=POSTGRES_PASSWORD="${MEALIE_PG_PASSWORD}" \
		--from-literal=POSTGRES_USER="${MEALIE_PG_USER}" \
		--from-literal=POSTGRES_SERVER="${MEALIE_PG_HOST}" \
		--from-literal=POSTGRES_PORT="${MEALIE_PG_PORT}" \
		--from-literal=POSTGRES_DB="${MEALIE_PG_DB}" \
		--from-literal=DEFAULT_EMAIL="${MEALIE_DEFAULT_ADMIN_USER}" \
		--from-literal=DEFAULT_PASSWORD="${MEALIE_DEFAULT_ADMIN_PASSWORD}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./app/mealie/storage.yml
	kubectl apply -f ./app/mealie/mealie.yml
	kubectl apply -f ./app/mealie/network.yml

.PHONY: mealie-remove
mealie-remove:
	-kubectl delete -f ./app/mealie/network.yml
	-kubectl delete -f ./app/mealie/mealie.yml
	-kubectl delete -f ./app/mealie/storage.yml
	-kubectl -n mealie delete secret mealie-env
	-kubectl apply -f ./app/mealie/namespace.yml --cascade=background

.PHONY: mealie-debug
mealie-debug:
	kubectl -n mealie exec -it `kubectl -n mealie get pods -l app.kubernetes.io/name=mealie -o name` -- bash

.PHONY: mealie-debug-pg
mealie-debug-pg:
	kubectl -n mealie run -i --tty --rm debug --image=postgres --restart=Never -- /bin/bash -c "psql postgresql://${MEALIE_PG_ADMIN_USER}:${MEALIE_PG_ADMIN_PASSWORD}@${MEALIE_PG_HOST}:${MEALIE_PG_PORT}/${MEALIE_PG_DB}"
	#kubectl -n mealie debug -it --image=postgres `kubectl -n mealie get pods -l app.kubernetes.io/name=mealie -o name` -- /bin/bash -c "psql postgresql://mealie:${MEALIE_PG_PASSWORD}@192.168.1.200:35432/mealie"

.PHONY: mealie-logs
mealie-logs:
	#TODO: update
	kubectl -n mealie logs `kubectl -n mealie get pods -l app.kubernetes.io/name=mealie -o name | head -n 1` --follow

.PHONY: mealie-stop
mealie-stop:
	kubectl -n mealie scale deployment/mealie --replicas=0

.PHONY: mealie-start
mealie-start:
	kubectl -n mealie scale deployment/mealie --replicas=${MEALIE_REPLICAS}

.PHONY: mealie-restart
mealie-restart:
	kubectl -n mealie rollout restart deployment/mealie

.PHONY: mealie-status
mealie-status:
	@echo "======================================================================="
	@echo "= mealie Network Resources:                                         ="
	@echo "=   kubectl -n mealie get svc,endpoints,ingress -l app.kubernetes.io/name=mealie'    ="
	@echo "======================================================================="
	@kubectl -n mealie get svc -l 'app.kubernetes.io/name=mealie' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n mealie get endpoints,ingress -l 'app.kubernetes.io/name=mealie'
	@echo "\n======================================================================="
	@echo "= mealie Storage Resources:                                          ="
	@echo "=   kubectl -n mealie get pvc -l 'app.kubernetes.io/name=mealie'                      ="
	@echo "======================================================================="
	@kubectl -n mealie get pvc -l 'app.kubernetes.io/name=mealie' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================="
	@echo "= mealie Deployment Resources:                                       ="
	@echo "=   kubectl -n mealie get deployment,rs,pods -l 'app.kubernetes.io/name=mealie'       ="
	@echo "======================================================================="
	@kubectl -n mealie get deployment,rs,pods -l 'app.kubernetes.io/name=mealie'
