# Component Version Resource for Concourse

## Docker Image

https://hub.docker.com/r/spiegela/concourse-component-version

## Behavior

### `check`: Check object, and return the component version

If a version is specified in the source configuration, then the check will return the version back, if it exists. This is help to trigger only _when_ that component version exists, but not otherwise.

If a tag is specified in the source configuration, then check will return the version for that tag. When a tag is updated, any jobs set to trigger, will do so with the newly tagged version.

If no version or tag is specified, check will return a list of all of the component version for the component.


### `in`: Return the resource as a set of text files based, and optionally clone the component source repositories

In return the following files from the component version, which may be used in pipelines:

* `version`: a text file containing the latest version based on the source configuration
* `component`: a text file containing the component name
* `tag`: a text file containing the version with the leading "v", which is our current container tag standard
* `slug`: a text file containing the a "dasherized" version string, which, being URL/host compatible is useful for using in tests and such

### `out`: Publish a new version for the provided component, or promote an existing version to a component tag

The out script will perform the following functions based on the provided parameters, further described below in the parameter configuration section. These functions can peformed individually, or in combination by speciying each parameter.

* `publish`: creates a new version in the component-versions repository
* `promote`: update the provided tag to the component-version

## Usage

```yaml
resource_types:
  - name: component-version
    type: docker-image
    source:
      repository: spiegela/concourse-component-version

resources:
  - name: my-app-version
    type: component-version
    icon: counter
    source:
      uri:  git@eos2git.cec.lab.emc.com:ECS/component-versions.git
      branch: master
      component: my-app
      private_key: ((eos2git.private_key))

jobs:
  - name: build-and-publish-version
    plan:
      - get: my-app-source
      - load_var: version
        file: my-app-source/.git/describe_ref
      - load_var: commit
        file: my-app-source/.git/ref
      - put: my-app-version
        params:
          version: ((.:version))
          publish: true
          promote: latest
          manifest_json: |
            {
                "manifestFormatVersion": "2",
                "componentName": "my-app",
                "componentVersion": "((.:version))",
                "buildRepos": [
                    {
                        "url": "eos2git.cec.lab.emc.com/ECS/my-app.git",
                        "commit": "((.:commit))"
                    }
                ],
                "componentArtifacts": [
                    {
                        "version": "((.:version))",
                        "type": "docker-image",
                        "artifactId": "my-app-docker-image",
                        "endpoint": "{{ OBJECTSCALE_REGISTRY }}",
                        "path": "my-app"
                    }
                ]
            }
  - name: run-master-acceptance
    plan:
      - get: my-app-source
        passed:
          - build-and-publish-version
      - task: do-stuff
  - name: promote-version
    plan:
      - get: my-app-source
        passed:
          - run-master-acceptance
      - load_var: version
        file: my-app-source/.git/describe_ref
      - put: my-app-version
        params:
          version: ((.:version))
          promote: green
```

## Source Configuration

To create a Concourse resource, you must configure the details of this resource in the `source` block of the resource.  These variables are set globally for the pipeline

* `uri` The git URI of the component version repository
* `branch` The git branch of the component version repository.
* `private_key` The SSH private key to use for authentication against the component version repository
* `component` Name of the component to be managed by the resource
* `tracing_enabled` Enable detailed logging (including credentials) for debugging of the resource
* `version` When configuring a resource for a specific version, this field can be set. When unset, behavior will default to the latest version.  This can also be overridden in the `parameters` block.
* `tag` When configuring a resource for a specific tag, this field can be set. When unset, behavior will default to the latest version.  This can also be overridden in the `parameters` block.

## Parameter Configuration

Parameter values are used in `put` or `get` steps to override or customize the behavior of the action.

* `version` (string) This tag specifies a specific version to act against. When publishing a new version via a `put` step, this parameter is required.
* `publish` (boolean) When used in a `put` operation, this parameter indicates that the version should be published to the component versions repository.
* `tag` (string) This tag specifies a tag to retrieve in a `get` step if one is not provided in the `source` configuration. It is not used in a `put` step.
* `clone_sources` (boolean) When used in a `get` operation, this parameter indicates that the step should clone the component's git repositories.
* `manifest_json` (string) Specify the JSON content of a new version to publish to the component in a `put` step.
* `manifest_file` (string) Specify the filename of a JSON file with a new version to publish to the component in a `put` step.
* `readme_md` (string) Specify the README markdown content of a new version to publish to the component in a `put` step.
* `readme_file` (string) Specify the filename of a README markdown file with a new version to publish to the component in a `put` step.
* `promote` (string) When provided, this parameter should promote the version to tag in this value, typically `latest` or `green`.