FROM chrislusf/seaweedfs:4.48

# Wings runs containers as its system user (default uid 988). Match it so the
# process has a passwd entry. Override with --build-arg if yours differs.
ARG CONTAINER_UID=988

USER root

RUN apk add --no-cache bash

# Wings drops capabilities from every container, and the kernel refuses to
# exec a binary whose file capabilities exceed the bounding set. Rewriting each
# executable drops any security.capability xattr.
RUN for f in /usr/bin/weed; do \
      [ -f "$f" ] || continue; \
      mode=$(stat -c %a "$f"); cp "$f" "$f.nocap" && chmod "$mode" "$f.nocap" && mv -f "$f.nocap" "$f"; \
    done

# The upstream filer.toml points the metadata store at /data. Everything this
# server owns lives in the Pterodactyl volume instead.
RUN mkdir -p /etc/seaweedfs \
 && printf '[leveldb2]\nenabled = true\ndir = "/home/container/data/filerldb2"\n' > /etc/seaweedfs/filer.toml \
 && adduser -D -u ${CONTAINER_UID} -h /home/container -s /bin/bash container

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

ENV USER=container HOME=/home/container
USER container
WORKDIR /home/container

STOPSIGNAL SIGINT
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
