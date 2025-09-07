#!/bin/bash

# ==============================
# 函数定义区域
# ==============================

download_game() {
    echo "开始下载游戏..."

    sudo add-apt-repository multiverse
    sudo dpkg --add-architecture i386
    sudo apt update
    sudo apt install libstdc++6 libgcc1 libcurl4-gnutls-dev:i386 lib32z1
    sudo apt update
    sudo apt install software-properties-common
    mkdir $HOME/steamcmd
    cd $HOME/steamcmd
    wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
    tar -xvzf steamcmd_linux.tar.gz

    # 安装饥荒联机版
    ./steamcmd.sh +force_install_dir ../dontstarvetogether_dedicated_server \
    +login anonymous \
    +app_update 343050 validate \
    +quit

    echo "游戏下载完成。"
}

update_game() {
    echo "开始更新游戏和模组..."

    STEAMCMD_PATH="$HOME/steamcmd"          # SteamCMD 路径
    STEAM_PATH="$HOME/Steam"
    DST_PATH="$HOME/Steam/steamapps/common/Don't Starve Together Dedicated Server"
    if [ $# -ge 1 ]; then
        MODIDS=$@
    else
        MODIDS=$(cat $HOME/mods.txt | awk ' $1 != "#" {print $1}')
    fi
    SERVER_MODS_DIR="$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/mods"  # 服务器 Mod 目录

    # 下载 Mod
    UPDATECMD="$STEAMCMD_PATH/steamcmd.sh +login anonymous"
    UPDATECMD="$UPDATECMD +app_update 343050 validate "
    for MODID in $MODIDS; do
        UPDATECMD="$UPDATECMD +workshop_download_item 322330 ${MODID} validate "
    done
    UPDATECMD="$UPDATECMD +quit "

    $UPDATECMD

    # 复制 Mod 到服务器目录
    for MODID in $MODIDS; do
        MOD_SRC="$STEAM_PATH/steamapps/workshop/content/322330/$MODID"
        MOD_DST="$DST_PATH/mods/workshop-$MODID"
        rm -rf "$MOD_DST"
        cp -r "$MOD_SRC" "$MOD_DST"
    done

    echo "游戏更新完成。"
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

    function fail()
    {
        echo Error: "$@" >&2
        exit 1
    }

    function check_for_file()
    {
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

start_game() {
    echo "检测可用存档..."
    base_path="$HOME/.klei"
    valid_clusters=()

    # 遍历 1~5 号存档槽
    for i in {1..5}; do
        cluster_path="$base_path/DST_$i/Cluster_1"
        ini_file="$cluster_path/cluster.ini"

        if [ -f "$ini_file" ]; then
            cluster_name=$(grep -E "^cluster_name\s*=" "$ini_file" | cut -d= -f2- | sed 's/^[ \t]*//')
            if [ -n "$cluster_name" ]; then
                # 用 “DST号|存档名” 的形式保存
                valid_clusters+=("$i|$cluster_name")
            fi
        fi
    done

    # 没找到存档
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

    # 校验输入是否有效
    match_found=false
    for cluster in "${valid_clusters[@]}"; do
        IFS='|' read -r cid cname <<< "$cluster"
        if [ "$cid" = "$selected_index" ]; then
            match_found=true
            dst_id="DST_$cid"
            selected_name="$cname"
            break
        fi
    done

    if [ "$match_found" = false ]; then
        echo "选择无效，返回主菜单。"
        return
    fi

    echo "正在软连接存档 $dst_id ($selected_name) ..."
    ln -snf "$base_path/$dst_id/Cluster_1" "$base_path/DoNotStarveTogether/MyDediServer"

    restart_server

    log_path="$base_path/DoNotStarveTogether/MyDediServer/Master/server_log.txt"
    echo "以下是服务器日志(Ctrl+C 可停止查看，但服务器仍在运行):"
    # tail -f "$log_path"

    echo "返回主菜单。"
}

# ==============================
# 主菜单函数
# ==============================

main_menu() {
    while true; do
        echo ""
        echo "===== 饥荒联机版服务器管理器 ====="
        echo "1) 下载游戏"
        echo "2) 更新游戏"
        echo "3) 启动游戏"
        echo "4) 关闭服务器"
        echo "5) 退出"
        read -p "请输入选项(1-5): " choice

        case $choice in
            1)
                download_game
                ;;
            2)
                update_game
                ;;
            3)
                start_game
                ;;
            4)
                stop_server
                ;;
            5)
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
