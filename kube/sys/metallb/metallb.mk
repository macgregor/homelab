


.PHONY: metallb-deploy-first-time
metallb-deploy-first-time:
	helmfile --file ./sys/metallb/helmfile.yaml apply
	kubectl apply -f ./sys/metallb/addresspool.yml

.PHONY: metallb-deploy
metallb-deploy:
	SECRETKEY=$$(kubectl get secret --namespace "metallb" metallb-memberlist -o jsonpath="{.data.secretkey}" | base64 -d); \
	helmfile --file ./sys/metallb/helmfile.yaml apply --set "speaker.secretValue=$${SECRETKEY}"
	kubectl apply -f ./sys/metallb/addresspool.yml

.PHONY: metallb-remove
metallb-remove:
	helmfile --file ./sys/metallb/helmfile.yaml destroy
	kubectl delete -f ./sys/metallb/addresspool.yml

.PHONY: metallb-restart
metallb-restart:
	kubectl -n metallb rollout restart deployment/adguard-home