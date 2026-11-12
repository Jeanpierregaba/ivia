# Image de l'API ivia (ADR 0008). Construite par la CI à chaque fusion sur main :
#   docker build --build-arg APP_VERSION=<sha> -t ivia-api backend/
# Deux binaires : api (serveur + tâches de fond) et manage (grant-admin, migrate).

FROM golang:1.27.4-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api \
 && go build -trimpath -ldflags="-s -w" -o /out/manage ./cmd/manage

# Image d'exécution minimale : certificats racine et fuseaux horaires inclus, pas de shell,
# utilisateur non privilégié.
FROM gcr.io/distroless/static-debian12:nonroot
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION \
    PORT=8080
COPY --from=build /out/api /out/manage /usr/local/bin/
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/api"]
