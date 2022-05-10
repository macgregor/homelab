
.PHONY: oauth2-proxy-deploy
oauth2-proxy-deploy:
	helmfile --file ./sys/oauth2-proxy/helmfile.yaml apply

.PHONY: oauth2-proxy-remove
oauth2-proxy-remove:
	helmfile --file ./sys/oauth2-proxy/helmfile.yaml destroy
