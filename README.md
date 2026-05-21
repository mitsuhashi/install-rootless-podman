# install-rootless-podman
Ansible playbooks for installing rootless Podman on Ubuntu 24.04 LTS

### 前提

- Ubuntu 24.04 LTSで動作します。Ubuntu 22.04 LTSでは動作しません。
- PodmanをインストールしたいUbuntu OSに**Rootless Podmanを実行するユーザでログインした状態で実行**します。
- インストールにAnsibleが必要です。インストールされていない場合は以下のコマンドでインストールします。
```
sudo apt install ansible
```

### インストール手順

#### 1. sudo権限が必要な設定
Podmanを実行するユーザで以下のansible-playbookコマンドを実行します。ただし、当該ユーザにはsudo権限が付与されている必要があります。
```
ansible-playbook -v -i localhost, -c local install_rootless_podman_by_root.yml
```
以下の設定を行います。root権限を持つ管理者が同等の設定を別途行う場合は、このplaybookの実行は不要です。
- パッケージのインストール(podman, crun, pipx, python3-venv)
- Podmanを実行するユーザの linger 有効化
- Podmanを実行するユーザの systemd user manager 起動
- `systemctl --user` が rootless ユーザの D-Bus に接続できることの確認
- Podmanを実行するユーザの/etc/subuidと/etc/subgidへのエントリの追加
（例）mitsuhashiユーザの場合
```
$ grep mitsuhashi /etc/subuid
mitsuhashi:100000:65536
$ grep mitsuhashi /etc/subgid
mitsuhashi:100000:65536
```

#### 2. sudo権限が不要な設定とpodmanの起動確認
以下のansible-playbookコマンドを実行します。sudo権限が不要な設定を行い、podmanの起動確認を行います。
```
ansible-playbook -v -i localhost, -c local install_rootless_podman_by_rootless.yml
```
以下のように"Podman is working!"を表示されれば成功です。
```
$ ansible-playbook -v -i localhost, -c local install_rootless_podman_by_rootless.yml
<中略>

TASK [Run a test container with Podman] *************************************************************************************************************************************
changed: [localhost] => {"changed": true, "cmd": ["podman", "run", "--rm", "alpine", "echo", "Podman is working!"], "delta": "0:00:00.387262", "end": "2025-05-02 11:11:17.779712", "msg": "", "rc": 0, "start": "2025-05-02 11:11:17.392450", "stderr": "", "stderr_lines": [], "stdout": "Podman is working!", "stdout_lines": ["Podman is working!"]}

TASK [Display test container output] ****************************************************************************************************************************************
ok: [localhost] => {
    "msg": "Podman is working!"
}

PLAY RECAP ******************************************************************************************************************************************************************
localhost                  : ok=17   changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

$
```

### podman-compose.ymlをOS再起動時に自動起動する設定

`podman-compose --in-pod false up -d` で起動しただけでは、OS再起動後に自動で再起動されません。
自動起動したい `podman-compose.yml` ごとに、rootlessユーザの systemd user service を作成して有効化します。

このリポジトリでは、`test_mongodb` を podman-compose のサンプルとして用意しています。
以下の作業は、Podmanを実行するrootlessユーザで実行します。sudo権限は不要です。

#### 1. test_mongodb/podman-compose.ymlの確認

```
cd ~/install-rootless-podman/test_mongodb
cat podman-compose.yml
```

`test_mongodb/podman-compose.yml` では、MongoDBをrootless Podmanで起動します。

```yaml
services:
  mongodb:
    image: docker.io/library/mongo:7.0
    container_name: test_mongodb_rootless
    userns_mode: keep-id
    ports:
      - "37017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: example
    volumes:
      - ./data/mongodb:/data/db:Z
    restart: unless-stopped
```

- `userns_mode: keep-id` でコンテナ内のUID/GIDをホストのUID/GIDと対応させます。
- DBファイルは `test_mongodb/data/mongodb` 以下に作成されます。
- `restart: unless-stopped` はコンテナ異常終了時の再起動用です。OS再起動後の起動には、後述の systemd user service が必要です。

#### 2. podman-composeでMongoDBを起動する

```
cd ~/install-rootless-podman/test_mongodb
./podman_run_mongodb.sh
```

実行している内容は以下です。

```
#!/bin/sh
set -eu

mkdir -p ./data/mongodb
podman-compose --in-pod false up -d
```

`podman ps` でコンテナが起動していることを確認します。

```
podman ps
```

#### 3. MongoDBにログインできることを確認する

```
./podman_exec_mongodb.sh
```

実行している内容は以下です。

```
podman exec -it test_mongodb_rootless mongosh -u root -p example --eval 'db.stats()'
```

#### 4. systemd user serviceを作成して自動起動を有効化する

OS再起動時に `test_mongodb/podman-compose.yml` を自動起動するため、serviceを作成して有効化します。
service名は引数で指定できます。`.service` は付けても付けなくても構いません。

```
cd ~/install-rootless-podman/test_mongodb
./podman_enable_service.sh podman-compose-mongodb
```

引数を省略した場合も、service名は `podman-compose-mongodb.service` になります。

```
./podman_enable_service.sh
```

スクリプトは以下を実行します。

`su` や `sudo -u` などでログインセッション外から実行する場合は、事前に以下を設定してください。通常のSSHログインやコンソールログインで rootless ユーザとして実行する場合は不要です。

```
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus
```

- `~/.config/systemd/user/<service-name>.service` を作成
- `systemctl --user daemon-reload` を実行
- `systemctl --user enable --now <service-name>.service` を実行

作成されるserviceファイルは、スクリプトを実行した環境の `test_mongodb` ディレクトリと `podman-compose` のパスを使います。
そのため、リポジトリを `~/install-rootless-podman` 以外に配置している場合でも、その配置先に合わせたserviceファイルが作成されます。

#### 5. 自動起動の状態を確認する

```
systemctl --user status podman-compose-mongodb.service
podman ps
```

#### 6. OS再起動後に確認する

OSを再起動した後、rootlessユーザでログインして確認します。

```
podman ps
systemctl --user status podman-compose-mongodb.service
```

MongoDBコンテナが起動していれば設定完了です。

#### 7. MongoDBを停止して削除する

手動で停止する場合は以下を実行します。

```
cd ~/install-rootless-podman/test_mongodb
./podman_stop_rm_mongodb.sh
```

実行している内容は以下です。

```
#!/bin/sh
set -eu

podman-compose --in-pod false down
```

自動起動も無効化する場合は以下を実行します。

```
systemctl --user disable --now podman-compose-mongodb.service
```

#### 8. podman-compose.ymlとserviceを削除する場合

`podman-compose.yml` を削除する場合は、先に自動起動を無効化してコンテナを停止します。
`podman-compose.yml` を先に削除すると、`podman-compose down` や systemd の `ExecStop` が失敗する場合があります。

`test_mongodb` の例では以下を実行します。サービス名を変更して登録した場合は、実際のservice名を引数に指定してください。

```
cd ~/install-rootless-podman/test_mongodb
./podman_disable_service.sh podman-compose-mongodb
```

引数を省略した場合も、service名は `podman-compose-mongodb.service` になります。

```
./podman_disable_service.sh
```

スクリプトは以下を実行します。

- `systemctl --user disable --now <service-name>.service` を実行
- `podman-compose --in-pod false down` を実行
- `~/.config/systemd/user/<service-name>.service` を削除
- `systemctl --user daemon-reload` を実行

MongoDBのデータも削除する場合のみ、`--remove-data` を指定します。

```
./podman_disable_service.sh --remove-data podman-compose-mongodb
```

その後、不要であれば `podman-compose.yml` を削除します。

```
rm -f ~/install-rootless-podman/test_mongodb/podman-compose.yml
```

削除後に状態を確認します。

```
systemctl --user status podman-compose-mongodb.service
podman ps -a
```

#### 9. podman-compose.ymlを追加した場合

新しい `podman-compose.yml` を追加した場合は、そのcomposeプロジェクト用に別の service ファイルを作成します。

例:

```
~/install-rootless-podman/test_mongodb -> podman-compose-mongodb.service
~/podman-apps/nextcloud               -> podman-compose-nextcloud.service
~/podman-apps/gitea                   -> podman-compose-gitea.service
```

各 service について、serviceファイルを作成した後に一度だけ以下を実行します。`test_mongodb` の場合は `podman_enable_service.sh <service-name>` がこの作業まで実行します。

```
systemctl --user daemon-reload
systemctl --user enable --now <service-name>
```

`podman-compose.yml` の内容だけを変更した場合は、通常は service を enable し直す必要はありません。以下のように restart します。

```
systemctl --user restart podman-compose-mongodb.service
```
