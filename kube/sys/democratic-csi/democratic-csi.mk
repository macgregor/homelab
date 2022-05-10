
.PHONY: democratic-csi-deploy
democratic-csi-deploy:
	helmfile --file ./sys/democratic-csi/helmfile.yaml apply

.PHONY: democratic-csi-remove
democratic-csi-remove:
	helmfile --file ./sys/democratic-csi/helmfile.yaml destroy
