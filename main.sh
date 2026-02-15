#!/bin/bash

# ==============================
# 函数定义区域
# ==============================

download_game() {
    echo "开始下载游戏..."

    sudo add-apt-repository multiverse
    sudo dpkg --add-architecture i386
    sudo apt update
    sudo apt install -y libstdc++6 libgcc1 libcurl4-gnutls-dev:i386 lib32z1 software-properties-common
    mkdir -p "$HOME/steamcmd"
    cd "$HOME/steamcmd" || exit
    wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
    tar -xvzf steamcmd_linux.tar.gz

    ./steamcmd.sh +force_install_dir ../dontstarvetogether_dedicated_server \
    +login anonymous \
    +app_update 343050 validate \
    +quit
	
	base_path="$HOME/.klei"
	for i in {1..5}; do
        cluster_path="$base_path/DoNotStarveTogether/Cluster_$i"
        mkdir -p "$cluster_path"
    done

    echo "游戏下载完成。"
}

stop_server() {
    echo "正在停止服务器..."
    PIDS=$(ps -ef | grep dontstarve | grep -v grep | awk '{print $2}')
    if [ -n "$PIDS" ]; then
        echo "检测到以下 dontstarve 相关进程，将终止："
        echo "$PIDS"
        kill $PIDS
        echo "服务器已关闭。"
    else
        echo "未找到任何 dontstarve 相关进程。"
    fi
}

restart_server() {
    echo "开始重启服务器..."
    stop_server
    date

    steamcmd_dir="$HOME/steamcmd"
    install_dir="$HOME/Steam/steamapps/common/Don't Starve Together Dedicated Server"
    cluster_name="MyDediServer"
    dontstarve_dir="$HOME/.klei/DoNotStarveTogether"

    function fail() {
        echo "Error: $@" >&2
        exit 1
    }

    function check_for_file() {
        if [ ! -e "$1" ]; then
            fail "Missing file: $1"
        fi
    }

    cd "$steamcmd_dir" || fail "Missing $steamcmd_dir directory!"

    check_for_file "steamcmd.sh"
    check_for_file "$dontstarve_dir/$cluster_name/cluster.ini"
    check_for_file "$dontstarve_dir/$cluster_name/cluster_token.txt"
    check_for_file "$dontstarve_dir/$cluster_name/Master/server.ini"
    check_for_file "$dontstarve_dir/$cluster_name/Caves/server.ini"
    check_for_file "$install_dir/bin64"

    cd "$install_dir/bin64" || fail

    run_shared=(./dontstarve_dedicated_server_nullrenderer_x64)
    run_shared+=(-console)
    run_shared+=(-cluster "$cluster_name")
    run_shared+=(-monitor_parent_process $$)

    nohup "${run_shared[@]}" -shard Caves  | sed 's/^/Caves:  /' &
    nohup "${run_shared[@]}" -shard Master | sed 's/^/Master: /' &
    echo "服务器启动完成。"
}

# 解析 modoverrides.lua 文件中的 mod ID，并更新 mods.txt
parse_modoverrides() {
    local mod_file="$1"
    local mods_txt="$HOME/mods.txt"

    if [ ! -f "$mod_file" ]; then
        echo "未找到 $mod_file 文件，跳过模组同步。"
        return
    fi

    echo "正在解析 $mod_file ..."

    # 从 modoverrides.lua 中提取所有 workshop-xxxxxx
    local mod_ids
    mod_ids=$(grep -oP 'workshop-\K[0-9]+' "$mod_file" | sort -u)

    # 提取 mods.txt 中的已启用和禁用模组
    local enabled_mods disabled_mods
    enabled_mods=$(grep -v '^#' "$mods_txt" | awk '{print $1}' | grep -E '^[0-9]+$' || true)
    disabled_mods=$(grep '^#' "$mods_txt" | grep -oE '[0-9]+' || true)

    local updated=false
    for id in $mod_ids; do
        if echo "$disabled_mods" | grep -q "$id"; then
            echo "跳过禁用模组：$id"
            continue
        fi
        if ! echo "$enabled_mods" | grep -q "$id"; then
            echo "检测到新模组，追加到 mods.txt：$id"
            echo "$id 新增自modoverrides" >> "$mods_txt"
            updated=true
        fi
    done

    if [ "$updated" = true ]; then
        echo "mods.txt 已更新。"
    else
        echo "mods.txt 未变化。"
    fi
}

# 更新游戏与模组
update_game_and_mods() {
    echo "开始更新游戏和模组..."

    STEAMCMD_PATH="$HOME/steamcmd"
    STEAM_PATH="$HOME/Steam"
    DST_PATH="$HOME/Steam/steamapps/common/Don't Starve Together Dedicated Server"
    SERVER_MODS_DIR="$HOME/.klei/DoNotStarveTogether/MyDediServer/Master/mods"
    MODIDS=$(grep -v '^#' "$HOME/mods.txt" | awk '{print $1}' | grep -E '^[0-9]+$')

    UPDATECMD="$STEAMCMD_PATH/steamcmd.sh +login anonymous"
    UPDATECMD="$UPDATECMD +app_update 343050 validate "
    for MODID in $MODIDS; do
        UPDATECMD="$UPDATECMD +workshop_download_item 322330 ${MODID} validate "
    done
    UPDATECMD="$UPDATECMD +quit "

    eval "$UPDATECMD"

    for MODID in $MODIDS; do
        MOD_SRC="$STEAM_PATH/steamapps/workshop/content/322330/$MODID"
        MOD_DST="$DST_PATH/mods/workshop-$MODID"
        if [ -d "$MOD_SRC" ]; then
            rm -rf "$MOD_DST"
            cp -r "$MOD_SRC" "$MOD_DST"
        fi
    done

    echo "游戏与模组更新完成。"
}

start_game() {
    echo "检测可用存档..."
    base_path="$HOME/.klei"
    valid_clusters=()

    for i in {1..5}; do
        cluster_path="$base_path/DoNotStarveTogether/Cluster_$i"
        ini_file="$cluster_path/cluster.ini"
        if [ -f "$ini_file" ]; then
            cluster_name=$(grep -E "^cluster_name\s*=" "$ini_file" | cut -d= -f2- | sed 's/^[ \t]*//')
            if [ -n "$cluster_name" ]; then
                valid_clusters+=("$i|$cluster_name")
            fi
        fi
    done

    if [ ${#valid_clusters[@]} -eq 0 ]; then
        echo "未找到有效存档。"
        return
    fi

    echo "发现以下可用存档："
    for cluster in "${valid_clusters[@]}"; do
        IFS='|' read -r cid cname <<< "$cluster"
        echo "$cid: $cname"
    done

    read -p "请选择要启动的存档编号: " selected_index
    match_found=false
    for cluster in "${valid_clusters[@]}"; do
        IFS='|' read -r cid cname <<< "$cluster"
        if [ "$cid" = "$selected_index" ]; then
            match_found=true
            dst_id="Cluster_$cid"
            selected_name="$cname"
            break
        fi
    done

    if [ "$match_found" = false ]; then
        echo "选择无效，返回主菜单。"
        return
    fi

    echo "正在软连接存档 $dst_id ($selected_name) ..."
    ln -snf "$base_path/DoNotStarveTogether/$dst_id" "$base_path/DoNotStarveTogether/MyDediServer"

    # 新增：启动前更新模组
    mod_file="$base_path/DoNotStarveTogether/MyDediServer/Master/modoverrides.lua"
    parse_modoverrides "$mod_file"
    update_game_and_mods

    restart_server
}

# ==============================
# 主菜单函数
# ==============================

main_menu() {
    while true; do
        echo ""
        echo "===== 饥荒联机版服务器管理器 ====="
        echo "1) 下载游戏"
        echo "2) 启动游戏（自动更新模组）"
        echo "3) 关闭服务器"
        echo "4) 退出"
        read -p "请输入选项(1-4): " choice

        case $choice in
            1)
                download_game
                ;;
            2)
                start_game
                ;;
            3)
                stop_server
                ;;
            4)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "无效选项，请重新输入。"
                ;;
        esac
    done
}

# ==============================
# 启动主菜单
# ==============================

main_menu
