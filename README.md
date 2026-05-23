# install-rootless-podman

Ubuntu 24.04 LTS で rootless Podman と podman-compose を使うためのセットアップ手順と Ansible playbook です。

## 前提

- Ubuntu 24.04 LTS で動作します。Ubuntu 22.04 LTS は対象外です。
- rootless Podman を実行するユーザでログインして作業します。
- root 権限が必要な作業は、root ユーザまたは sudo 権限を持つユーザで実行します。
- ストレージ保存先は Podman のデフォルトを使います。このリポジトリでは `~/.config/containers/storage.conf` を自動作成しません。

## root ユーザが手動で行う設定

Ansible を使わずに管理者が手動設定する場合は、root ユーザで以下を実行します。`<user>` は rootless Podman を使うユーザ名に置き換えてください。

### 1. パッケージをインストールする

```sh
apt update
apt install -y podman crun fuse-overlayfs pipx python3-venv
```

### 2. subuid / subgid を設定する

既存の割り当てを確認します。

```sh
grep '^<user>:' /etc/subuid /etc/subgid
```

エントリがない場合は追加します。開始値は既存ユーザと重ならない範囲を選んでください。

```sh
echo '<user>:100000:65536' >> /etc/subuid
echo '<user>:100000:65536' >> /etc/subgid
```

複数ユーザに設定する場合は、開始値をユーザごとにずらします。

```text
user1:100000:65536
user2:165536:65536
user3:231072:65536
```

### 3. linger を有効化する

OS 起動時に rootless ユーザの systemd user manager を起動できるようにします。

```sh
loginctl enable-linger <user>
```

確認します。

```sh
loginctl show-user <user> --property=Linger
```

`Linger=yes` と表示されれば有効です。

### 4. systemd user manager を起動する

```sh
uid=$(id -u <user>)
systemctl start user@${uid}.service
```

D-Bus socket が作成されたことを確認します。

```sh
ls /run/user/${uid}/bus
```

### 5. podman-restart.service を有効化する

`restart: always` が設定された rootless Podman コンテナを OS 再起動後に起動するため、対象ユーザの user systemd で `podman-restart.service` を有効化します。

```sh
uid=$(id -u <user>)
sudo -iu <user> env \
  XDG_RUNTIME_DIR=/run/user/${uid} \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus \
  systemctl --user enable podman-restart.service
```

確認します。

```sh
sudo -iu <user> env \
  XDG_RUNTIME_DIR=/run/user/${uid} \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus \
  systemctl --user is-enabled podman-restart.service
```

`enabled` と表示されれば有効です。

## Ansible で root 権限が必要な設定を行う

上記の root 作業は `install_rootless_podman_by_root.yml` で実行できます。rootless Podman を使うユーザでログインし、sudo 権限がある状態で実行します。

Ansible が未インストールの場合は先にインストールします。

```sh
sudo apt install ansible
```

playbook を実行します。

```sh
ansible-playbook -v -i localhost, -c local install_rootless_podman_by_root.yml
```

この playbook は以下を行います。

- `podman`, `crun`, `fuse-overlayfs`, `pipx`, `python3-venv` のインストール
- rootless ユーザの linger 有効化
- rootless ユーザの systemd user manager 起動
- `systemctl --user` が rootless ユーザの D-Bus に接続できることの確認
- `podman-restart.service` の有効化
- `/etc/subuid` と `/etc/subgid` へのエントリ追加

## rootless ユーザで行う設定

rootless Podman を使うユーザで以下を実行します。sudo 権限は不要です。

```sh
ansible-playbook -v -i localhost, -c local install_rootless_podman_by_rootless.yml
```

この playbook は以下を行います。

- `podman-compose` の pipx インストール
- `~/.config/containers/registries.conf` の作成
- `~/.config/containers/containers.conf` で `crun` を runtime に設定
- `podman system migrate` の実行
- `podman run --rm alpine echo "Podman is working!"` による動作確認

`registries.conf` は Docker Hub を検索対象にするため、以下の内容で作成します。

```toml
[registries.search]
registries = ['docker.io']
```

ストレージ保存先は Podman のデフォルトを使います。保存先を変更したい環境では、必要に応じて `~/.config/containers/storage.conf` を別途設定してください。

## MongoDB サンプル

`test_mongodb` は rootless Podman と podman-compose の動作確認用サンプルです。

### 1. compose.yml を確認する

```sh
cd ~/install-rootless-podman/test_mongodb
cat compose.yml
```

```yaml
x-podman:
  in_pod: false

services:
  mongodb:
    image: docker.io/library/mongo:7.0
    userns_mode: keep-id
    ports:
      - "127.0.0.1:${MONGODB_PORT:-37017}:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME:?set MONGO_INITDB_ROOT_USERNAME in .env}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD:?set MONGO_INITDB_ROOT_PASSWORD in .env}
    volumes:
      - ./data/mongodb:/data/db:Z
    restart: always
```

ポイント:

- `userns_mode: keep-id` でコンテナ内の UID/GID をホストの UID/GID と対応させます。
- `userns_mode: keep-id` と pod 作成は同時に使えないため、`x-podman.in_pod: false` を指定します。
- DB ファイルは `test_mongodb/data/mongodb` 以下に作成されます。
- `restart: always` により、`podman-restart.service` が有効な環境では OS 再起動後の自動起動対象になります。
- サンプルの公開ポートは `127.0.0.1` に限定しています。別ホストから接続する必要がある場合は、リバースプロキシや SSH トンネルを使うか、意図を確認したうえでバインドアドレスを変更してください。

### 2. .env を作成する

```sh
cd ~/install-rootless-podman/test_mongodb
cp env.example .env
# 必要に応じて .env を編集
```

### 3. MongoDB を起動する

```sh
cd ~/install-rootless-podman/test_mongodb
./podman_run_mongodb.sh
```

スクリプトは以下を実行します。

```sh
mkdir -p ./data/mongodb
podman-compose up -d
```

### 4. 起動状態を確認する

```sh
podman ps
podman inspect --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' test_mongodb_mongodb_1
systemctl --user is-enabled podman-restart.service
loginctl show-user $(whoami) --property=Linger
```

期待値:

```text
test_mongodb_mongodb_1 always
enabled
Linger=yes
```

### 5. MongoDB にログインする

```sh
./podman_exec_mongodb.sh
```

スクリプトは `.env` を読み込んで、以下を実行します。

```sh
podman-compose exec mongodb mongosh -u "${MONGO_INITDB_ROOT_USERNAME:-root}" -p "${MONGO_INITDB_ROOT_PASSWORD:-example}" --eval 'db.stats()'
```

### 6. OS 再起動後に確認する

OS を再起動した後、rootless ユーザでログインして確認します。

```sh
cd ~/install-rootless-podman/test_mongodb
podman ps
./podman_exec_mongodb.sh
```

MongoDB コンテナが起動していれば設定完了です。

### 7. MongoDB を停止して削除する

```sh
cd ~/install-rootless-podman/test_mongodb
./podman_stop_rm_mongodb.sh
```

スクリプトは以下を実行します。

```sh
podman-compose down
```

MongoDB のデータも削除する場合のみ、以下を実行します。

```sh
rm -rf ~/install-rootless-podman/test_mongodb/data/mongodb
```

## compose.yml を追加する場合

新しい compose プロジェクトを追加する場合も、個別の user systemd service は作成しません。各 `compose.yml` に `restart: always` を指定し、`podman-compose up -d` でコンテナを作成します。

`podman-restart.service` は `install_rootless_podman_by_root.yml` で有効化済みのため、必要に応じて以下で状態を確認します。

```sh
systemctl --user is-enabled podman-restart.service
```

## 参考

- [nig-podman](https://github.com/suecharo/nig-podman) - rootless Podman / podman-compose の運用方針、`compose.yml`、`restart: always`、`podman-restart.service` の使い方を参考にしています。
