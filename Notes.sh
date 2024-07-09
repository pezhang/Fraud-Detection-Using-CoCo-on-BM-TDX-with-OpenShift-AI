Issue 1: Deploy MinIO storage fails: ImagePull error
Description
```
# oc apply -n fraud-detection -f https://github.com/rh-aiservices-bu/fraud-detection/raw/main/setup/setup-s3.yaml

# oc get pods -n fraud-detection
NAME                       	READY   STATUS              	RESTARTS   AGE
create-ds-connections-frm6l	0/1 	ImagePullBackOff    	0      	171m
create-minio-buckets-th5d2 	0/1 	Init:ImagePullBackOff   0      	171m
create-minio-root-user-hv6dg   0/1 	ImagePullBackOff    	0      	171m
create-s3-storage-tj9nd    	0/1 	ImagePullBackOff    	0      	171m
minio-5bc68f6884-dtnmj     	0/1 	Pending             	0      	171m
```

Solution
To start the image registry, you must change the Image Registry Operator configuration’s managementState from Removed to Managed.
```
# oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'
# oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
```
Configure the storage for the Image registry or set an empty directory.
```
# oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
```
