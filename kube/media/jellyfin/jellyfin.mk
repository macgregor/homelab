JELLYFIN_REPLICAS?=1

.PHONY: jellyfin-deploy
jellyfin-deploy:
	kubectl apply -f ./media/jellyfin/namespace.yml
	kubectl apply -f ./media/jellyfin/storage.yml
	kubectl apply -f ./media/jellyfin/jellyfin.yml
	kubectl apply -f ./media/jellyfin/network.yml

.PHONY: jellyfin-remove
jellyfin-remove:
	-kubectl delete -f ./media/jellyfin/network.yml
	-kubectl delete -f ./media/jellyfin/jellyfin.yml
	-kubectl delete -f ./media/jellyfin/storage.yml
	#-kubectl apply -f ./media/jellyfin/namespace.yml --cascade=background

.PHONY: jellyfin-debug
jellyfin-debug:
	kubectl -n media exec -it `kubectl -n media get pods -l app.kubernetes.io/name=jellyfin -o name` -- bash

.PHONY: jellyfin-logs
jellyfin-logs:
	#TODO: update
	kubectl -n media logs `kubectl -n media get pods -l app.kubernetes.io/name=jellyfin -o name` --follow

.PHONY: jellyfin-stop
jellyfin-stop:
	kubectl -n media scale deployment/jellyfin --replicas=0

.PHONY: jellyfin-start
jellyfin-start:
	kubectl -n media scale deployment/jellyfin --replicas=${JELLYFIN_REPLICAS}

.PHONY: jellyfin-restart
jellyfin-restart:
	kubectl -n media rollout restart deployment/jellyfin

.PHONY: jellyfin-status
jellyfin-status:
	@echo "======================================================================="
	@echo "= jellyfin Network Resources:                                         ="
	@echo "=   kubectl -n media get svc,endpoints,ingress -l app.kubernetes.io/name=jellyfin'    ="
	@echo "======================================================================="
	@kubectl -n media get svc -l 'app.kubernetes.io/name=jellyfin' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n media get endpoints,ingress -l 'app.kubernetes.io/name=jellyfin'
	@echo "\n======================================================================="
	@echo "= jellyfin Storage Resources:                                          ="
	@echo "=   kubectl -n media get pvc -l 'app.kubernetes.io/name=jellyfin'                      ="
	@echo "======================================================================="
	@kubectl -n media get pvc -l 'app.kubernetes.io/name=jellyfin' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo "\n======================================================================="
	@echo "= jellyfin Deployment Resources:                                       ="
	@echo "=   kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=jellyfin'       ="
	@echo "======================================================================="
	@kubectl -n media get deployment,rs,pods -l 'app.kubernetes.io/name=jellyfin'

.PHONY: jellyfin-cert
jellyfin-cert:
	kubectl -n media get secret/jellyfin-tls -o json | jq '.data["tls.crt"]' -r | base64 -d | openssl x509 -noout -text

.PHONY: jellyfin-lb-test
jellyfin-lb-test:
	curl -kvL --resolve 'jellyfin.matthew-stratton.me:443:192.168.1.220' https://jellyfin.matthew-stratton.me/