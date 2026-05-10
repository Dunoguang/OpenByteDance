#! /usr/bin/env bash


create_dir_and_symlink() {
  local target_path="$1"
  local link_path="$2"

  mkdir -p "$target_path"
  chown user:user "$target_path"
  chmod 777 "$target_path"
  create_symlink "$target_path" "$link_path"
}

# function: 创建软链接
create_symlink() {
  local target_path="$1"
  local link_path="$2"
  echo "create_symlink: target_path=$target_path ; link_path=$link_path"
  
  if [ -d "$link_path" ]; then
      echo "错误: $link_path 是目录" >&2
  elif [ -f "$link_path" ]; then
        echo "错误: $link_path 是文件" >&2
  elif [ -L "$link_path" ]; then
        echo "错误: $link_path 已存在符号链接" >&2
  else
      ln -s "$target_path" "$link_path"
  fi
}

init_workspace() {
  echo "init_workspace"

  mkdir -p /sandboxdata/workspace/sessions
  create_dir_and_symlink "/sandboxdata/workspace/global/browser" "/home/user/.super_doubao/super-doubao-runtime/browser"

  # 处理动态session目录
  if [ -n "${SESSION_ID}" ]; then
      echo "SESSION_ID = ${SESSION_ID}"
      if [ -d "/home/user/.super_doubao/super-doubao-runtime/workspace" ]; then
        mv /home/user/.super_doubao/super-doubao-runtime/workspace /home/user/.super_doubao/super-doubao-runtime/workspace.backup
      fi
      mv /mnt /mnt.backup

      mkdir -p /sandboxdata/workspace/sessions
      mkdir -p /sandboxdata/workspace/sessions/${SESSION_ID}
      # 目录和软链接
      chown user:user "/sandboxdata/workspace/sessions/${SESSION_ID}"
      chmod 777 "/sandboxdata/workspace/sessions/${SESSION_ID}"
      create_dir_and_symlink "/sandboxdata/workspace/sessions/${SESSION_ID}/file" /home/user/.super_doubao/super-doubao-runtime/workspace
      create_dir_and_symlink "/sandboxdata/workspace/sessions/${SESSION_ID}/code" /mnt
      
      # pip dir
      # install path
      mkdir -p /sandboxdata/workspace/sessions/${SESSION_ID}/pip
      echo "[global]" > /etc/pip.conf
      echo "target = /sandboxdata/workspace/sessions/${SESSION_ID}/pip" >> /etc/pip.conf
      # search lib path
      USERVENV_PATH="/home/user/.super_doubao/super-doubao-runtime/uservenv"
      echo "/sandboxdata/workspace/sessions/${SESSION_ID}/pip" > ${USERVENV_PATH}/lib/python3.12/site-packages/user_pkgs.pth

  fi
}

init_http_proxy() {
  # 如果传入了PROXY环境变量，则使用PROXY作为代理
  if [ -n "$PROXY" ]; then
    echo "PROXY=${PROXY}, init_http_proxy"
    echo "export http_proxy=\"${PROXY}\"" >> ~/.bashrc
    echo "export https_proxy=\"${PROXY}\"" >> ~/.bashrc
    echo "export HTTP_PROXY=\"${PROXY}\"" >> ~/.bashrc
    echo "export HTTPS_PROXY=\"${PROXY}\"" >> ~/.bashrc
    echo "export no_proxy=\"localhost,127.0.0.1,::1\"" >> ~/.bashrc

    . ~/.bashrc
  fi
}

init_http_proxy

cd ~/.super_doubao/super-doubao-runtime

PY_ARGS="$@"
echo "PY_ARGS=$PY_ARGS"

# vefaas不允许ulimit，目前暂时只能使用2048上限
# ulimit -n 20480 || echo "ulimit set failed"
# echo "ulimit -n now: $(ulimit -n)"

# 使用gosu，以user用户启动进程 且 继承当前进程的 ulimit fd上限（1024 -> 2048）
exec gosu user /usr/bin/python3.10 start_server.py "$@"
