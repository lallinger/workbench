FROM ubuntu:24.04

WORKDIR /root

COPY setup.sh .
RUN ./setup.sh

# VOLUME [ "/var/run/docker.sock" ]
