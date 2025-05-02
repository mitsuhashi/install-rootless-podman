mkdir -p ./data/mongodb

podman run -d \
  --name mongodb_rootless \
  --userns=keep-id \
  -v ./data/mongodb:/data/db:Z \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=example \
  docker.io/library/mongo:7.0
