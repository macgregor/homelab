
.PHONY: ingress-internal-deploy
ingress-internal-deploy:
	helmfile --file ./sys/ingress-nginx/internal/helmfile.yaml apply

.PHONY: ingress-internal-remove
ingress-internal-remove:
	helmfile --file ./sys/ingress-nginx/internal/helmfile.yaml destroy
