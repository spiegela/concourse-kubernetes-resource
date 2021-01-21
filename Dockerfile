FROM alpine
LABEL maintainer = "Dell EMC ObjectScale"
ADD assets /opt/resource

# rename .bash files to the unextended name, so that the entrypoint stays simple
RUN for i in /opt/resource/*.bash; do mv -i "$i" /opt/resource/$(basename "$i" .bash); done && \
    chmod 755 /opt/resource/* /opt/resource/manifest/*
RUN apk --no-cache add jq curl bash openssh-client git python3

ENV PYTHONUNBUFFERED=1

RUN python3 -m ensurepip && \
    rm -r /usr/lib/python*/ensurepip && \
    pip3 install --no-cache --upgrade pip setuptools wheel && \
    cd /opt/resource/manifest && \
    pip3 install -r requirements.txt

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]