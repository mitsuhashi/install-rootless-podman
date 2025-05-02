podman exec -it mongodb_rootless mongosh -u root -p example --eval 'db.stats()'
