#!/usr/bin/python3

import json
import os
import sys
from urllib.parse import urlparse

import yaml

OUTPUT_DIR = "manifest"


def repo_metadata(resource):
    commit_file = open(os.path.join(resource.name, ".git", "ref"), 'r')
    version_file = open(os.path.join(resource.name, ".git", "describe_ref"), 'r')
    timestamp_file = open(os.path.join(resource.name, ".git", "commit_timestamp"), 'r')
    return {
        "name": resource.name,
        "url": resource.name,
        "branch": resource.branch,
        "timestamp": timestamp_file.read().replace("\n", ""),
        "commit": commit_file.read().replace("\n", ""),
        "version": version_file.read().replace("\n", "")
    }


def artifact_metadata(resource):
    metadata = {
        "type": resource.type,
        "artifactId": resource.name
    }
    if resource.type == "registry-image":
        tag_file = open(os.path.join(resource.name, "tag"))
        digest_file = open(os.path.join(resource.name, "digest"))
        repo_url = urlparse(resource.source.repository)
        repository_file = open(os.path.join(resource.name, "repository"))
        metadata.update({
            "endpoint": repo_url.netloc,
            "path": repo_url.path,
            "version": tag_file.read().replace("\n", ""),
            "digest": digest_file.read().replace("\n", ""),
            "repository": repository_file.read().replace("\n", "")
        })
    if resource.type == "docker-image":
        tag_file = open(os.path.join(resource.name, "tag"))
        image_id_file = open(os.path.join(resource.name, "image_id"))
        digest_file = open(os.path.join(resource.name, "digest"))
        repo_url = urlparse(resource.source.repository)
        repository_file = open(os.path.join(resource.name, "repository"))
        metadata.update({
            "endpoint": repo_url.netloc,
            "path": repo_url.path,
            "version": tag_file.read().replace("\n", ""),
            "imageId": image_id_file.read().replace("\n", ""),
            "digest": digest_file.read().replace("\n", ""),
            "repository": repository_file.read().replace("\n", "")
        })
    if resource.type == "s3":
        url_file = open(os.path.join(resource.name, "url"))
        version_file = open(os.path.join(resource.name, "version"))
        file_url = urlparse(url_file.read().replace("\n", ""))
        metadata.update({
            "endpoint": file_url.netloc,
            "path": file_url.path,
            "version": version_file.read().replace("\n", "")
        })


def artifact_resource(resource_type):
    return resource_type == "s3" or resource_type == "docker-image"


def main(component, version, pipeline_file):
    with open(os.path.join(pipeline_file)) as file:
        pipeline = yaml.load(file, Loader=yaml.FullLoader)
        manifest = {
            "manifestFormatVersion": "2",
            "componentName": component,
            "componentVersion": version,
            "buildRepos": list(
                map(lambda git_repo: repo_metadata(git_repo),
                    filter(lambda resource: resource.type == "git", pipeline.resources))),
            "componentArtifacts": list(
                map(lambda artifact: artifact_metadata(artifact),
                    filter(artifact_resource, pipeline.resources))
            )
        }
        with open(os.path.join(OUTPUT_DIR, 'manifest.json'), 'w') as outfile:
            json.dump(manifest, outfile)


if __name__ == "__main__":
    main(component=sys.argv[1], version=sys.argv[2], pipeline_file=sys.argv[5])
