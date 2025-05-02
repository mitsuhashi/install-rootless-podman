# sudo実行とそうでないtaskを一緒にしている
#ansible-playbook -v -i localhost, -c local install_rootless_podman_all.yml

# sudo実行のみ
ansible-playbook -v -i localhost, -c local install_rootless_podman_by_root.yml

# sudo実行でないtaskのみ (先にinstall_rootless_podman_by_root.ymlを実行する必要がある)
ansible-playbook -v -i localhost, -c local install_rootless_podman_by_rootless.yml
