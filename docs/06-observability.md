PLACEHOLDER


* elasticsearch is super heavy
* using fluentd, loki and grafana as a lightweight alternative


# Resources
* Elastic Cloud Operator: https://artifacthub.io/packages/helm/elastic/eck-operator
* Install elasticsearch: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-elasticsearch-specification.html


curl -kvL --resolve 'kibana.matthew-stratton.me:443:192.168.1.220' https://kibana.matthew-stratton.me/

kubectl -n elastic-system exec -it elasticsearch-es-masters-0 -c elasticsearch -- bash
elasticsearch-users useradd macgregor -p 'changeme' -r superuser
elasticsearch-users useradd test -p 'changeme' -r viewer
