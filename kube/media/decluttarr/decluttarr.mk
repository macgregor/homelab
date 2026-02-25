DECLUTTARR_REPLICAS?=1

.PHONY: decluttarr-deploy
decluttarr-deploy:
	kubectl apply -f ./media/decluttarr/namespace.yml
	kubectl create secret generic decluttarr-api-keys \
		-n media \
		--save-config \
		--dry-run=client \
		--from-literal=RADARR_API_KEY="${RADARR_API_KEY}" \
		--from-literal=SONARR_API_KEY="${SONARR_API_KEY}" \
		--from-literal=QBITTORRENT_USER="${QBITTORRENT_USER}" \
		--from-literal=QBITTORRENT_PASS="${QBITTORRENT_PASS}" \
		-o yaml | kubectl apply -f -;
	kubectl apply -f ./media/decluttarr/decluttarr.yml

.PHONY: decluttarr-remove
decluttarr-remove:
	-kubectl delete -f ./media/decluttarr/decluttarr.yml
	-kubectl -n media delete secret/decluttarr-api-keys

.PHONY: decluttarr-logs
decluttarr-logs:
	kubectl -n media logs -l app.kubernetes.io/name=decluttarr --follow

.PHONY: decluttarr-stop
decluttarr-stop:
	kubectl -n media scale deployment/decluttarr --replicas=0

.PHONY: decluttarr-start
decluttarr-start:
	kubectl -n media scale deployment/decluttarr --replicas=${DECLUTTARR_REPLICAS}

.PHONY: decluttarr-restart
decluttarr-restart:
	kubectl -n media rollout restart deployment/decluttarr

.PHONY: decluttarr-status
decluttarr-status:
	@echo "======================================================================================"
	@echo "= decluttarr Deployment Resources:                                                   ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=decluttarr'   ="
	@echo "======================================================================================"
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=decluttarr'
