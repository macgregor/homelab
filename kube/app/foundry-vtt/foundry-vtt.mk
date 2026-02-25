foundry-vtt_REPLICAS?=1
admin-pass?=${FOUNDRY_INSTANCE_ADMIN_PASS}
foundry-user?=${FOUNDRY_LICENSE_USER}
foundry-pass?=${FOUNDRY_LICENSE_PASS}

.PHONY: foundry-vtt-deploy
foundry-vtt-deploy:
	kubectl apply -f ./app/foundry-vtt/namespace.yml
	kubectl apply -f ./app/foundry-vtt/storage.yml
	@kubectl create secret generic foundry-vtt-credentials \
		-n foundry-vtt \
		--save-config \
		--dry-run=client \
		--from-literal=adminKey="${admin-pass}" \
		--from-literal=username="${foundry-user}" \
		--from-literal=password="${foundry-pass}" \
		-o yaml | kubectl apply -f -
	kubectl apply -f ./app/foundry-vtt/foundry-vtt.yml
	kubectl apply -f ./app/foundry-vtt/network.yml

.PHONY: foundry-vtt-remove
foundry-vtt-remove:
	kubectl delete -f ./app/foundry-vtt/network.yml
	kubectl delete -f ./app/foundry-vtt/foundry-vtt.yml
	kubectl -n foundry-vtt delete secret/foundry-vtt-credentials
	kubectl delete -f ./app/foundry-vtt/storage.yml
	kubectl delete -f ./app/foundry-vtt/namespace.yml --cascade=background

.PHONY: foundry-vtt-debug
foundry-vtt-debug:
	kubectl -n foundry-vtt exec -it `kubectl -n foundry-vtt get pods -l app.kubernetes.io/name=foundry-vtt -o name` -- bash

.PHONY: foundry-vtt-logs
foundry-vtt-logs:
	kubectl -n foundry-vtt logs -l app.kubernetes.io/name=foundry-vtt --follow

.PHONY: foundry-vtt-stop
foundry-vtt-stop:
	kubectl -n foundry-vtt scale deployment/foundry-vtt --replicas=0

.PHONY: foundry-vtt-start
foundry-vtt-start:
	kubectl -n foundry-vtt scale deployment/foundry-vtt --replicas=${foundry-vtt_REPLICAS}

.PHONY: foundry-vtt-restart
foundry-vtt-restart:
	kubectl -n foundry-vtt rollout restart deployment/foundry-vtt

.PHONY: foundry-vtt-status
foundry-vtt-status:
	@echo "======================================================================="
	@echo "= foundry-vtt Network Resources:                                      ="
	@echo "=   kubectl -n foundry-vtt get svc,endpoints,ingress -l app.kubernetes.io/name=foundry-vtt' ="
	@echo "======================================================================="
	@kubectl -n foundry-vtt get svc -l 'app.kubernetes.io/name=foundry-vtt' -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.loadBalancerIP
	@echo ""
	@kubectl -n foundry-vtt get endpoints,ingress
	@echo -e "\n======================================================================="
	@echo "= foundry-vtt Storage Resources:                                      ="
	@echo "=   kubectl -n foundry-vtt get pvc -l 'app.kubernetes.io/name=foundry-vtt' ="
	@echo "======================================================================="
	@kubectl -n foundry-vtt get pvc -l 'app.kubernetes.io/name=foundry-vtt' -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
	@echo -e "\n======================================================================="
	@echo "= foundry-vtt Deployment Resources:                                   ="
	@echo "=   kubectl -n foundry-vtt get deployment,rs,pods -l 'app.kubernetes.io/name=foundry-vtt' ="
	@echo "======================================================================="
	@kubectl -n foundry-vtt get deployment,rs,pods -l 'app.kubernetes.io/name=foundry-vtt'
