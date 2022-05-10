.PHONY: apply-elasticsearch
apply-elasticsearch:
	@echo "Assuming Elastic Cloud Operator already installed by helm"
	envsubst < ./elastic/elastic-search.yml | kubectl apply -f -
	@echo "Init can take quite a while, follow progress with:"
	@echo "  kubectl -n elastic-system get pods -l 'common.k8s.elastic.co/type==elasticsearch' -w"

.PHONY: clean-elasticsearch
clean-elasticsearch:
	-kubectl delete -f ./elastic/elastic-search.yml
	-kubectl -n elastic-system get pvc -l 'common.k8s.elastic.co/type=elasticsearch' -o name | xargs -I{} kubectl -n elastic-system delete "{}"

.PHONY: apply-kibana
apply-kibana:
	 kubectl apply -f ./elastic/kibana.yml
	 kubectl -n elastic-system get pods,svc,ingress -l 'common.k8s.elastic.co/type=kibana'
