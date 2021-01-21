PROJECT = concourse-component-version
ID = spiegela/${PROJECT}

all: build push

build:
	docker build --tag ${ID}:latest .

push:
	docker push ${ID}

run:
	docker run \
		--interactive \
		--tty \
		${ID}:latest \
		bash