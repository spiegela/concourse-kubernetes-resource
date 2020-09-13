FROM alpine
LABEL maintainer "Aaron Spiegel <spiegela@gmail>"
ADD assets /opt/resource

# rename .bash files to the unextended name, so that the entrypoint stays simple
RUN for i in /opt/resource/*.bash; do mv -i "$i" /opt/resource/$(basename "$i" .bash); done
RUN apk add jq curl bash

RUN curl -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.19.0/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kubectl
RUN mkdir /root/.kube

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]