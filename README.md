# Kubernetes Resource for Concourse

Manage all kinds of [Kubernetes](https://kubernetes.io) resources from [Concourse](https://concourse-ci.org/).

Based on the work of https://github.com/typositoire/concourse-helm3-resource

## Docker Image

https://hub.docker.com/r/spiegela/concourse-kubernetes-resource

## Behavior

### `check`: Check object, and return the object resource revision along with metadata

### `in`: Return the resource as a set of text files based on the object name and kind

#### Parameters

* `file`: *Optional.* file template to query/delete/apply to the Kubernetes cluster.
* `url`: *Optional.* URL template to query/delete/apply to the Kubernetes cluster.
* `command`: *Optional.* specify a custom command for `kubectl` commands as an alternative query/mutation method when not using a file/url template.
* `command_args`: *Optional.* a list of arguments for `kubectl` `get`, `create` or `delete` commands as an alternative creation method when not using a file/url template.
* `token_path`: *Optional.* Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
* `kubeconfig_path`: *Optional.* File containing a kubeconfig. Overrides source configuration for cluster, token, and admin config.
* `wait`: *Optional.* Monitors the resource specified in the `wait_for` configuration for readiness, or deletion of all resources if deleting.
* `wait_for`: *Optional.* Condition for which we should wait, as specified in `kubectl wait --for` command. Required for `wait` of applied resources, not for get, check, or delete operations.
* `output`: *Optional.* kubectl output option to apply to the kubernetes objects. Matches the options for `kubectl -o`  (`yaml`, `json`, `wide`, `jsonpath`, etc.)
* `output_file`: *Optional.* file to place the output data within. If not provided, the output file will have a basename of "objects" with an extension based on the output type.
* `timeout`: *Optional.* Amount of time in seconds to wait for resources to reach the desired condition. (Default: 30)

### `out`: Apply a set Kubernetes objects to the configured namespace

#### Parameters

* `file`: *Optional.* file template to query/delete/apply to the Kubernetes cluster.
* `url`: *Optional.* URL template to query/delete/apply to the Kubernetes cluster.
* `command`: *Optional.* specify a custom command for `kubectl` commands as an alternative query/mutation method when not using a file/url template.
* `command_args`: *Optional.* a list of arguments for `kubectl` `get`, `create` or `delete` commands as an alternative creation method when not using a file/url template.
* `token_path`: *Optional.* Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
* `kubeconfig_path`: *Optional.* File containing a kubeconfig. Overrides source configuration for cluster, token, and admin config.
* `wait`: *Optional.* Monitors the resource specified in the `wait_for` configuration for readiness, or deletion of all resources if deleting.
* `wait_for`: *Optional.* Condition for which we should wait, as specified in `kubectl wait --for` command. Required for `wait` of applied resources, not for get, check, or delete operations.
* `output`: *Optional.* kubectl output option to apply to the kubernetes objects. Matches the options for `kubectl -o`  (`yaml`, `json`, `wide`, `jsonpath`, etc.)
* `output_file`: *Optional.* file to place the output data within. If not provided, the output file will have a basename of "objects" with an extension based on the output type.
* `timeout`: *Optional.* Amount of time in seconds to wait for resources to reach the desired condition. (Default: 30)

## Usage

```yaml
resource_types:
- name: kubernetes
  type: docker-image
  source:
    repository: spiegela/concourse-kubernetes-resource
```

## Source Configuration

### Root configuration

* `objects`: *Required.* A list of Kubernetes objects represented by the resource. The schema of this listed below, this list can be used to query/delete objects, but not to apply them.
* `namespace`: *Optional.* Kubernetes namespace the chart will be installed into. (Default: `default`)
* `url`: *Optional.* A URL to a supported Kubenretes template to address the sources.  Supports `check`, `put`, and `get` operations.
* `list`: *Optional for IN only.* Rather than getting a distinct set of resources, get a listing. Provide `true` or `false`.  (Default: `false`) Not supported for *OUT*.
* `field_selector`: *Optional for IN only.* Field selector to limit objects when retrieving a listing. Follows `kubectl` syntax. Not supported for *OUT*.
* `label_selector`: *Optional for IN only.* Label selector to limit objects when retrieving a listing. Follows `kubectl` syntax. Not supported for *OUT*.
* `cluster_url`: *Optional.* URL to Kubernetes Master API service. Do not set when using the `kubeconfig_path` parameter, otherwise required.
* `cluster_ca`: *Optional.* Base64 encoded PEM. (Required if `insecure_cluster` == false)
* `insecure_cluster`: *Optional.* Skip TLS verification for cluster API. (Required if `cluster_ca` is nil)
* `token`: *Optional.* Bearer token for Kubernetes.  This, 'token_path' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
* `token_path`: *Optional.* Path to file containing the bearer token for Kubernetes.  This, 'token' or `admin_key`/`admin_cert` are required if `cluster_url` is https.
* `admin_key`: *Optional.* Base64 encoded PEM. Required if `cluster_url` is https and no `token` or 'token_path' is provided.
* `admin_cert`: *Optional.* Base64 encoded PEM. Required if `cluster_url` is https and no `token` or 'token_path' is provided.
* `tracing_enabled`: *Optional.* Enable extremely verbose tracing for this resource. Useful when developing the resource itself. May allow secrets to be displayed. (Default: false)

### Object configuration schema

* `name`: *Required.* Name of the Kubernetes object.
* `kind`: *Required.* Fully qualified for short name of the object type (deployment, stateful-set, nodes.metrics.k8s.io, etc.)

## Usage Examples

### Basic Example

In this example, we define a resource by a defined list of K8s objects (kind and name), and we're able to check for new versions, put and get them. When defining resources with a file or URL based template in the parameters block, it is recommended to include the objects in the source block.  Otherwise, the `check` operations won't have adequate data to query Kubernetes.  If you can define a URL in the `source` block, though, the `check` operation will work without it. 

```yaml
resource_types:
  - name: kubernetes-object
    type: docker-image
    source:
      repository: spiegela/concourse-kubernetes
      tag: latest

resources:
- name: myapp
  type: kubernetes
  source:
    namespace: my-namespace-name
    objects:
      - kind: namespace
        name: my-namespace-name
      - kind: deployment
        name: my-app-name
      - kind: service
        name: my-app-name
    cluster_url: https://kube-master.domain.example
    cluster_ca: _base64 encoded CA pem_
    admin_key: _base64 encoded key pem_
    admin_cert: _base64 encoded certificate pem_

jobs:
  - name: run-myapp-in-K8s
    plan:
      - get: myapp_template
      - put: myapp
        params:
          file: myapp_template/template.yaml
  - name: get-myapp-from-K8s
    plan:
      - get: myapp
        passed:
          - run-myapp-in-K8s
```

### Listing Example

In some cases, you may want to have a dynamic list of objects, and have the resource version change any time an element is updated, or the members of the list change.  You aren't able to "put" to this resource, but you can certainly list and trigger jobs with it.

```yaml
k8s_env: &k8s_env
  cluster_url: ((cluster_url))
  cluster_ca: ((cluster_ca))
  admin_key: ((admin_key))
  admin_cert: ((admin_cert))

resources:
  - name: node-list
    type: kubernetes-object
    source:
      list: nodes
      <<: *k8s_env

jobs:
  - name: remove-node-taints
    plan:
# Get the nodes once they're all ready
      - get: node-list
        params:
          wait: true
          wait_for: '.status.conditions[?(@.type=="Ready")].status'
# Remove the master taint if it exists
      - try:
          put: node-list
          params:
            command: taint
            command_args: "--all node-role.kubernetes.io/master:NoSchedule-"
# Annotate the nodes that they have passed this step in case they didn't need to be modified
      - put: node-list
        params:
          command: annotate
          command_args: "--overwrite --all node-status.spieg.org/master-taint-removed=((cluster_version))"
```

### Resource that uses a URL

Often in Kubernetes, we create resources based on an available URL rather than a private file.  That's fine also.  You can also use that template (file or URL) to "get" and "check" the associated objects. 

```yaml
resources:
  - name: metrics-server
    type: kubernetes-object
    source:
      namespace: kube-system
      url: https://url-path-to-metrics-server-template/components.yaml
      <<: *k8s_env
jobs:
  - name: setup-metrics-server
    plan:
      - put: metrics-server
        params:
          wait: true
  - name: another-job
    plan:
      - get: metrics-server
```

### Smart resource creation

Every once in a while in K8s, you can't create a resource if it already exists.  We _could_ use Concourse's `try` syntax, but then we're not really sure what the error was about. It's much nicer to install resources based ona  failure to get them:

```yaml
resources:
  - name: cert-manager-crds
    type: kubernetes-object
    source:
      namespace: cert-manager
      url: https://url-path-to/cert-manager.crds.yaml
      <<: *k8s_env

jobs:
  - name: setup-cert-manager
    plan:
      - get: cert-manager-crds
        params:
        on_failure:
          put: cert-manager-crds
```

### Create by command arguments

Sometimes we like to create things through a single CLI instead of a template, and I say _"Why not? You do you."_  Of course, since the object details are defined in the `params` block, you should define the objects explicitly in the `source` block.

```yaml
resources:
  - name: memberlist-secret
    type: kubernetes-object
    source:
      namespace: metallb-system
      objects:
        - name: memberlist
          kind: Secret
      <<: *k8s_env

  - name: metallb
    plan:
    -  get: memberlist-secret
       on_failure:
         do:
           - task: generate-memberlist-key
             config:
               platform: linux
               outputs:
                 - name: memberlist
               image_resource:
                 type: docker-image
                 source:
                   repository: frapsoft/openssl
                   tag: latest
               run:
                 path: /bin/ash
                 args:
                   - -c
                   - |
                     if [ $DEBUG == "true" ]; then
                       set -x
                     fi
                     openssl rand -base64 128 > memberlist/secretkey
           - load_var: memberlist-secret
             file: memberlist/secretkey
           - put: memberlist-secret
             inputs:
               - memberlist
             params:
               command: create
               command_args: generic --from-literal=secretkey=((.:memberlist-secret))
```

### Using JSONPath for useful info in an object

Maybe you just one some info about a K8s object using JSONPath.  That can be super fun:

```yaml
jobs:
  - name: something-that-needs-to-know-my-k8s-version
    plan:
      - get: node-list
        params:
          output: jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'
          output_file: version.txt
      - task: k8s-newer-than-1.16
        config:
          platform: linux
          image_resource:
            type: docker-image
            source:
              repository: alpine
              tag: latest
          inputs:
            - name: node-list
          run:
            path: /bin/ash
            args:
              - -c
              - |
                if [[ $DEBUG == "true" ]]; then
                  set -x
                fi
                if [[ $(cat node-list/version.txt | cut -d"." -f2 | tr -d "\n") -gt 16 ]]; then
                  echo "Kubernetes is older than 1.17, so we're not going to do stuff."
                  exit 1
                else
                  echo "Kubernetes is 1.17 or newer, so we going to do stuff."
                  exit 0
                fi
      on_success:
        do:
          # stuff
```

## Other cool Concourse-y things

I have a strong opinion that Concourse resources are way more useful when they support all the core actions: `in`, `out`, and `check`, even when all the `in`/`check` actions do is fetch some metadata.  If you like this model, you can also checkout my fork of a [Helm 3 resource](https://github.com/spiegela/concourse-helm3-resource/).