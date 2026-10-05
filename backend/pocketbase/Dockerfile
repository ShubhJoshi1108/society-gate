FROM alpine:3.20
ARG PB_VERSION=0.40.3
ARG TARGETARCH=amd64
RUN apk add --no-cache unzip ca-certificates tzdata wget \
 && wget -q https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${TARGETARCH}.zip -O /tmp/pb.zip \
 && unzip /tmp/pb.zip -d /pb && rm /tmp/pb.zip
COPY pb_migrations /pb/pb_migrations
COPY pb_hooks /pb/pb_hooks
EXPOSE 8090
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090", "--dir=/pb/pb_data"]
