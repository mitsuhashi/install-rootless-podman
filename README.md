# install-rootless-podman
Ansible playbooks for installing rootless Podman on Ubuntu 24.04 LTS

### 前提

- Ubuntu 24.04 LTSで動作します。Ubuntu 22.04 LTSでは動作しません。
- PodmanをインストールしたいUbuntu OSに**Rootless Podmanを実行したユーザでログインした状態で実行**します。
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
以下の設定を行います。root権限を持つ管理者が設定する場合は実行不要です。
- パッケージのインストール(podman, crun, pipx, python3-venv)
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

### 動作確認テスト

test_mongodb以下のスクリプトを使ってmongodbの起動テストができます。

#### 1. test_mongodb/podman_run_mongodb.shの確認

```
~/install-rootless-podman/test_mongodb$$ cat podman_run_mongodb.sh
mkdir -p ./data/mongodb

podman run -d \
  --name mongodb_rootless \
  --userns=keep-id \
  -v ./data/mongodb:/data/db:Z \
  -p 37017:37017 \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=example \
  docker.io/library/mongo:7.0
mitsuhashi@vs88:~/install-rootless-podman/test_mongodb$
```
- userns=keep-id でコンテナ内のUID/GIDをホストのUID/GIDと一致させます。
- DBファイルは./data/mongodb以下に作成されます。

#### 2. podman_run_mongodb.shの実行

```
~/install-rootless-podman/test_mongodb$ ./podman_run_mongodb.sh
0536d66eaac4a153012920a1bad4d8dcb5bf76b14b28a5673be99154f6b936f3
```

#### 3. podman psでコンテナが起動していることを確認

```
~/install-rootless-podman/test_mongodb$ podman ps
CONTAINER ID  IMAGE                        COMMAND     CREATED        STATUS        PORTS                     NAMES
0536d66eaac4  docker.io/library/mongo:7.0  mongod      4 seconds ago  Up 5 seconds  0.0.0.0:37017->37017/tcp  mongodb_rootless
~/install-rootless-podman/test_mongodb$
```

#### 4. data/mongodb以下のファイルがホストと同じUID/GIDで作成されていることを確認

```
~/install-rootless-podman/test_mongodb$ ls -l data/mongodb/ | head -4
total 348
-rw------- 1 mitsuhashi dbcls0001 20480 May  2 11:20 collection-0--247210045027023696.wt
-rw------- 1 mitsuhashi dbcls0001 36864 May  2 11:21 collection-2--247210045027023696.wt
-rw------- 1 mitsuhashi dbcls0001  4096 May  2 10:48 collection-4--247210045027023696.wt
~/install-rootless-podman/test_mongodb$
```

#### 5. mongodbにログインできることを確認する

```
$ podman exec -it mongodb_rootless mongosh -u root -p example --eval 'db.stats()'
{
  db: 'test',
  collections: Long('0'),
  views: Long('0'),
  objects: Long('0'),
  avgObjSize: 0,
  dataSize: 0,
  storageSize: 0,
  indexes: Long('0'),
  indexSize: 0,
  totalSize: 0,
  scaleFactor: Long('1'),
  fsUsedSize: 0,
  fsTotalSize: 0,
  ok: 1
}
$
```

#### 6. podmanコンテナを停止して削除する

```
$ podman stop mongodb_rootless
mongodb_rootless
~/install-rootless-podman/test_mongodb$ podman ps
CONTAINER ID  IMAGE       COMMAND     CREATED     STATUS      PORTS       NAMES
$ podman ps -a
CONTAINER ID  IMAGE                        COMMAND     CREATED        STATUS                    PORTS                     NAMES
0536d66eaac4  docker.io/library/mongo:7.0  mongod      3 minutes ago  Exited (0) 8 seconds ago  0.0.0.0:37017->37017/tcp  mongodb_rootless
$ podman rm mongodb_rootless
mongodb_rootless
$ podman ps -a
CONTAINER ID  IMAGE       COMMAND     CREATED     STATUS      PORTS       NAMES
$
```
