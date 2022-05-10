
.PHONY: metallb-deploy
metallb-deploy:
	helmfile --file ./sys/metallb/helmfile.yaml apply

.PHONY: metallb-remove
metallb-remove:
	helmfile --file ./sys/metallb/helmfile.yaml destroy
