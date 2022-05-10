CERT_MANAGER_REPLICAS?=1

.PHONY: cert-manager-deploy
cert-manager-deploy:
	helmfile --file ./sys/cert-manager/helmfile.yaml apply
	envsubst < ./sys/cert-manager/cert-manager.yml | kubectl apply -f -

.PHONY: cert-manager-remove
cert-manager-remove:
	kubectl delete -f ./sys/cert-manager/cert-manager.yml
	helmfile --file ./sys/cert-manager/helmfile.yaml destroy

.PHONY: cert-manager-stop
cert-manager-stop:
	kubectl -n cert-manager scale deployment/cert-manager --replicas=0
	kubectl -n cert-manager scale deployment/cert-manager-webhook --replicas=0
	kubectl -n cert-manager scale deployment/cert-manager-cainjector --replicas=0

.PHONY: cert-manager-start
cert-manager-start:
	kubectl -n cert-manager scale deployment/cert-manager --replicas=${CERT_MANAGER_REPLICAS}
	kubectl -n cert-manager scale deployment/cert-manager-webhook --replicas=${CERT_MANAGER_REPLICAS}
	kubectl -n cert-manager scale deployment/cert-manager-cainjector --replicas=${CERT_MANAGER_REPLICAS}

.PHONY: cert-manager-restart
cert-manager-restart:
	kubectl -n cert-manager rollout restart deployment/cert-manager
	kubectl -n cert-manager rollout restart deployment/cert-manager-webhook
	kubectl -n cert-manager rollout restart deployment/cert-manager-cainjector
