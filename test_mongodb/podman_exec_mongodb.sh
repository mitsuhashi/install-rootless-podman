podman exec -it test_mongodb_rootless mongosh -u root -p example --eval 'db.stats()'
