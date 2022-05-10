
.PHONY: ingress-external-deploy
ingress-external-deploy:
	helmfile --file ./sys/ingress-nginx/external/helmfile.yaml apply

.PHONY: ingress-external-remove
ingress-external-remove:
	helmfile --file ./sys/ingress-nginx/external/helmfile.yaml destroy
