#!/bin/bash
# Variable initialization
options=$1
exec_log=/var/log/hosts-tool/exec-$(date +"%Y-%m-%d").log
cutlinetext="#=========请确保hosts文件中新增的所有内容均在该行之后========="
SYSTEM_TYPE=
source=

# if ! which tput > /dev/null 2>&1; then
_norm="\033[39m"
_red="\033[31m"
_green="\033[32m"
_tan="\033[33m"     
_cyan="\033[36m"
# else
#     _norm=$(tput sgr0)
#     _red=$(tput setaf 1)
#     _green=$(tput setaf 2)
#     _tan=$(tput setaf 3)
#     _cyan=$(tput setaf 6)
# fi

function _print() {
	printf "${_norm}%s${_norm}\n" "$@"
}
function _info() {
	printf "${_cyan}➜ %s${_norm}\n" "$@"
}
function _success() {
	printf "${_green}✓ %s${_norm}\n" "$@"
}
function _warning() {
	printf "${_tan}⚠ %s${_norm}\n" "$@"
}
function _error() {
	printf "${_red}✗ %s${_norm}\n" "$@"
}

function _loginfo(){
    cat >> /var/log/hosts-tool/exec-"$(date +"%Y-%m-%d")".log <<EOF

------------------------------------------------
时间：$(date +"%Y-%m-%d %H:%M:%S")
执行情况：
EOF
}

function _usage(){
	# print help info
	echo -e "\nGitHub hosts 自动部署和更新工具"
	echo -e "\n命令格式: \n$(basename "$0")  选项1  (选项2)"
	echo -e "\n选项:\n"
    echo "run                        立即更新hosts"
	echo "updatefrom gitlab|github    需指定下载源才能升级该工具"
    echo "                           可选选项为 gitlab 或 github，默认是 GitLab"
    echo ""
	echo "recover                    该选项将将此工具所有功能从系统中移除"
    echo "                           可选选项为 first_backup 或 uptodate_backup"
    echo ""
	echo "help                       显示帮助信息并退出"
}

function _checksys(){
    if [ -f /usr/bin/sw_vers ]; then
        SYSTEM_TYPE="MacOS"
    elif [ -f /usr/bin/lsb_release ]; then
        system_name=$(lsb_release -i 2>/dev/null)
        if [[ ${system_name} =~ "Debian" ]]; then
            SYSTEM_TYPE="Debian"
        elif [[ ${system_name} =~ "Ubuntu" ]]; then
            SYSTEM_TYPE="Ubuntu"
        fi
    elif [ -f /etc/redhat-release ]; then
        system_name=$(cat /etc/redhat-release 2>/dev/null)
        if [[ ${system_name} =~ "CentOS" ]]; then
            SYSTEM_TYPE="CentOS"
        elif [[ ${system_name} =~ "Red" ]]; then
            SYSTEM_TYPE="RedHat"
        fi
    elif which synoservicectl > /dev/null 2>&1; then
        SYSTEM_TYPE="Synology"
    # elif which opkg > /dev/null 2>&1; then
    #     SYSTEM_TYPE="ROUTER"
    # elif [[ $(find / -name *unRAID* 2>/dev/null |xargs) =~ "unRAID" ]]; then
    #     SYSTEM_TYPE="unRAID"
    fi
}

function _placescript(){
    _info "开始更新工具..."
    if ! which timeout > /dev/null 2>&1; then
        # if [[ "${SYSTEM_TYPE}" == "ROUTER" ]]; then
        #     _info "开始安装 timeout"
        #     opkg update > /dev/null 2>&1
        #     opkg install coreutils-timeout
        #     _success "timeout 安装完成"
        # else
        _warning "未发现 timeout 命令，将临时下载 timeout 命令程序"
        curl -Ls https://gitlab.com/api/v4/projects/36462411/repository/files/timeout/raw?ref=main
        chmod +x /tmp/timeout
        export PATH="/tmp:$PATH"
        _success "timeout 命令程序已下载并应用成功"
        # fi
    fi
    count=1
    while true;do
        if [[ $source == "gitlab" ]]; then
            _info "从 GitLab 下载脚本"
            timeout 20s curl -Ls https://gitlab.com/api/v4/projects/36462411/repository/files/hosts-tool.sh/raw?ref=main -o /tmp/hosts-tool
        elif [[ $source == "github" ]]; then
            _info "从 GitHub 下载脚本"
            _info "开始检测 GitHub 连通性..."
            if ! timeout 5s ping -c2 -W1 github.com > /dev/null 2>&1; then
                _error "本机所在网络无法连接 GitHub，将切换到 GitLab 同步源进行更新..."
                source="gitlab"
                continue
            else
                timeout 5s wget -qO /tmp/hosts-tool https://raw.githubusercontent.com/mylovesaber/auto_update_github_hosts/master/hosts-tool.sh
            fi
        fi
        if [ -f /tmp/hosts-tool ] && [ -n "$(cat /tmp/hosts-tool)" ];then
            _success "已下载，开始转移到系统程序路径"
            break
        else
            sleep 1
            count=$(( count + 1 ))
            _error "更新文件不存在，开始尝试第 ${count} 次下载..."
        fi
        if [ ${count} -gt 5 ]; then
            _error "工具下载失败，请择日再运行此脚本，退出中..."
            exit 1
        fi
    done
    if [ "$(grep -c gitlab /tmp/hosts-tool)" == 0 ]; then
        _error "安装出现错误，退出中..."
        exit 1
    fi
    if [[ "${SYSTEM_TYPE}" == "MacOS" ]]; then
        mv /tmp/hosts-tool /usr/local/bin/hosts-tool
        _info "修改权限中..."
        chown root:admin /usr/local/bin/hosts-tool
        chmod 755 /usr/local/bin/hosts-tool
    # elif [[ "${SYSTEM_TYPE}" == "ROUTER" ]]; then
    #     mv /tmp/hosts-tool /opt/bin/hosts-tool
    #     _info "修改权限中..."
    #     chmod 755 /opt/bin/hosts-tool
    else
        mv /tmp/hosts-tool /usr/bin/hosts-tool
        _info "修改权限中..."
        chown root: /usr/bin/hosts-tool
        chmod 755 /usr/bin/hosts-tool
    fi
    _success "权限修改完成"
    _success "工具安装完成"
}

function _backuphosts(){
    _info "开始备份 hosts.bak 和 hosts.default..."
    # 首次使用此脚本，备份已有 hosts，在清除更新 github hosts 规则的自动环境之前均不会改动此文件
    _info "检测 hosts.bak 文件是否存在"
    if [[ ! -f /etc/hosts.bak ]]; then
        _warning "原始 hosts.bak 备份未找到，备份当前 hosts 文件为 hosts.bak"
        cp -af /etc/hosts /etc/hosts.bak
        _success "备份完毕"
    fi
    _success "已发现hosts.bak，跳过"
    # 将系统自带及用户自定义的 hosts 规则筛选出来并重定向为 hosts.default 文件
    # 用户后续可在特定标记行之后自由修改 hosts 中的信息
    # hosts 文件中特定标记行之后改动的信息会随之后的系统定时任务更新到新的 hosts.default 文件中
    _info "检测环境安装后实时更新的 hosts.default 文件是否存在"
    if [[ ! -f /etc/hosts.default ]]; then
        _warning "未发现 hosts.default 文件，为原始 hosts 文件文本添加标记并备份为实时更新的 hosts.default..."
        if grep -q "${cutlinetext}" /etc/hosts; then
            _warning "发现原始 hosts 文件存在残留的标记信息，清理中..."
            sed -i '/'${cutlinetext}'/d' /etc/hosts
            _success "清理完毕"
        fi
        _info "为原始 hosts 文件添加标记中..."
        sed -i '1i\'${cutlinetext}'' /etc/hosts
        _success "标记完毕"
        _info "将原始 hosts 备份为实时更新的 hosts.default..."
        cp -af /etc/hosts /etc/hosts.default
        _success "备份完毕"
    else
        _info "未发现hosts.default，将原始 hosts 信息和用户新增内容备份为 hosts.default..."
        cutline=$(grep -n "${cutlinetext}" /etc/hosts | cut -d':' -f1)
        sed -n ''${cutline}',$p' /etc/hosts > /etc/hosts.default
        _success "备份完毕"
    fi
    _success "所有备份已完成"
}

function _combine(){
    _info "开始合并 hosts..."
    if [[ -f /etc/githubhosts.new ]]; then
        _warning "发现githubhosts.new，清理中..."
        rm -rf /etc/githubhosts.new
        _success "清理完毕"
    fi
    _info "下载最新 GitHub hosts 信息中..."
    # wget -qO /etc/githubhosts.new https://raw.hellogithub.com/hosts
    newIP=$(curl -Ls https://raw.hellogithub.com/hosts|sed '/^</d')
    if [ -n "${newIP}" ]; then
        _success "下载完成"
        _info "正在合并并替换成新hosts文件..."
        sed -i '/# GitHub520 Host Start/,/# GitHub520 Host End/d' /etc/hosts
        echo "${newIP}" > /etc/hosts_combine
        cat /etc/hosts.default >> /etc/hosts_combine
        mv -f /etc/hosts_combine /etc/hosts
        _success "合并替换完成"
    else
        _error "获取失败，等待下次获取"
        exit 1
    fi
}

function _setcron(){
    # 默认每1小时更新一次hosts，每3天自动更新一次工具本身，每10天清理一次旧日志
    if [[ "${SYSTEM_TYPE}" == "MacOS" ]]; then
        _info "清理残留定时任务中..."
        crontab -l | grep -v "hosts-tool" | crontab -
        _success "清理完成"
        _info "添加新定时任务中..."
        {
            echo "* */1 * * * /usr/local/bin/hosts-tool run"
            echo "* * */3 * * /usr/local/bin/hosts-tool updatefrom $source"
            echo "* * */10 * * /usr/local/bin/hosts-tool rmlog"
        } >> /tmp/cronfile
        crontab /tmp/cronfile
        rm -rf /tmp/cronfile
        _success "新定时任务添加完成"
    # elif [[ "${SYSTEM_TYPE}" == "ROUTER" ]]; then
    #     _info "清理残留定时任务中..."
    #     crontab -l | grep -v "hosts-tool" | crontab -
    #     _success "清理完成"
    #     _info "添加新定时任务中..."
    #     {
    #         echo "* */1 * * * /opt/bin/hosts-tool run"
    #         echo "* * */3 * * /opt/bin/hosts-tool updatefrom $source"
    #         echo "* * */10 * * /opt/bin/hosts-tool rmlog"
    #     } >> /tmp/cronfile
    #     crontab /tmp/cronfile
    #     rm -rf /tmp/cronfile
    #     _success "新定时任务添加完成"
    elif [[ ${SYSTEM_TYPE} =~ "unRAID" ]]; then
        _info "清理残留定时任务中..."
        hostpath=/boot/config/plugins/dynamix/github-hosts.cron
        rm -rf $hostpath
        _success "清理完成"
        _info "添加新定时任务中..."
        cat >> $hostpath <<EOF
* */1 * * * root /usr/bin/bash /usr/bin/hosts-tool run
* * */3 * * root /usr/bin/bash /usr/bin/hosts-tool updatefrom $source
* * */10 * * root /usr/bin/bash /usr/bin/hosts-tool rmlog
EOF
        /usr/local/sbin/update_cron
        _success "新定时任务添加完成"
    else
        _info "清理残留定时任务中..."
        sed -i '/\/usr\/bin\/hosts-tool/d' /etc/crontab
        _success "清理完成"
        _info "添加新定时任务中..."
        {
            echo "* */1 * * * root /usr/bin/bash /usr/bin/hosts-tool run"
            echo "* * */3 * * root /usr/bin/bash /usr/bin/hosts-tool updatefrom $source"
            echo "* * */10 * * root /usr/bin/bash /usr/bin/hosts-tool rmlog"
        } >> /etc/crontab
        _success "新定时任务添加完成"
    fi
}

function _refresh_dns(){
    _info "正在刷新 DNS 缓存..."
    # 路由器中的 bash 不知道啥原因不识别 =~ 会报错，以下其他系统都正常
    # if [[ "${SYSTEM_TYPE}" == "ROUTER" ]]; then
    #     if ! which restart_dns > /dev/null 2>&1; then
    #         _error "暂未发现该系统中的刷新 dns 功能，请自行搜索该系统的刷新 dns 方法并给脚本作者发 issue"
    #         exit 1
    #     fi
    #     restart_dns
    # elif [[ "${SYSTEM_TYPE}" =~ "Ubuntu"|"Debian"|"RedHat" ]]; then
    if [[ "${SYSTEM_TYPE}" =~ "Ubuntu"|"Debian"|"RedHat" ]]; then
        systemd-resolve --flush-caches
    elif [[ "${SYSTEM_TYPE}" == "MacOS" ]]; then
        killall -HUP mDNSResponder
    elif [[ "${SYSTEM_TYPE}" == "CentOS" ]]; then
        if ! which nscd > /dev/null 2>&1; then
            if ! which dnf > /dev/null 2>&1; then
                yum install -y nscd
            else
                dnf install -y nscd
            fi
        fi
        systemctl restart nscd
    elif [[ "${SYSTEM_TYPE}" == "Synology" ]]; then
        /var/packages/DNSServer/target/script/flushcache.sh
    fi
    _success "DNS 缓存刷新完成"
}

function _recover(){
    _warning "开始卸载工具"
    # if [[ "${SYSTEM_TYPE}" =~ "MacOS"|"ROUTER" ]]; then
    if [[ "${SYSTEM_TYPE}" == "MacOS" ]]; then
        crontab -l | grep -v "hosts-tool" | crontab -
    elif [[ "${SYSTEM_TYPE}" =~ "unRAID" ]]; then
        rm -rf /boot/config/plugins/dynamix/github-hosts.cron
        /usr/local/sbin/update_cron
    else
        sed -i '/\/usr\/bin\/hosts-tool/d' /etc/crontab
    fi
    _success "定时任务已清除"
    if [[ "${SYSTEM_TYPE}" == "MacOS" ]]; then
        rm -rf /usr/local/bin/hosts-tool
    # elif [[ "${SYSTEM_TYPE}" == "ROUTER" ]]; then
    #     rm -rf /opt/bin/hosts-tool
    else
        rm -rf /usr/bin/hosts-tool
    fi
    rm -rf /var/log/hosts-tool
    _success "工具和日志记录已清除"
    if [[ ${extraarg} =~ "first_backup" ]]; then
        mv -f /etc/hosts.bak /etc/hosts
        rm -rf /etc/hosts_combine /etc/hosts.default /etc/githubhosts.new
    elif [[ ${extraarg} =~ "uptodate_backup" ]]; then
        mv -f /etc/hosts.default /etc/hosts
        rm -rf /etc/hosts_combine /etc/hosts.bak /etc/githubhosts.new
    fi
    if grep -q "${cutlinetext}" /etc/hosts; then
        _warning "发现恢复后的 hosts 文件存在残留的标记信息，清理中..."
        sed -i '/'${cutlinetext}'/d' /etc/hosts
        _success "清理完毕"
    fi
    _success "卸载完成，指定 hosts 文件已恢复，拜拜~~"
}

function _rmlog(){
    logfile=$(find /var/log/hosts-tool/ -name "exec*.log" -mtime +10)
    for a in $logfile
    do
        rm -f "${a}"
    done
}

_checksys

if [[ $options == "updatefrom" ]]; then
	extraarg=${*:2}
	if [[ $extraarg != "gitlab" && $extraarg != "github" && -z $extraarg ]]; then
		_error "请正确输入自动更新工具下载源名称对应括号内的英文选项："
		_warning "GitLab (gitlab)"
		_warning "GitHub (github)"
	else
        source=$extraarg
        _loginfo
        _placescript | tee -a "${exec_log}"
        _setcron | tee -a "${exec_log}"
	fi
fi

if [[ $options == "recover" ]]; then
	extraarg="${*:2}"
    if [[ $extraarg != "first_backup" && $extraarg != "uptodate_backup" ]]; then
		_error "请正确输入需要恢复的hosts文件对应括号内的英文选项:"
		_warning "首次备份 (first_backup)"
		_warning "最新备份 (uptodate_backup)"
	else
		_recover
        _refresh_dns
	fi
fi

if [[ $options == "help" ]]; then
	_usage
	exit 0
fi

if [[ $options == "run" ]]; then
    _loginfo
    _backuphosts | tee -a "${exec_log}"
    _combine | tee -a "${exec_log}"
    _refresh_dns | tee -a "${exec_log}"
fi

if [[ $options == "rmlog" ]]; then
    _rmlog
fi

if [[ ! $options =~ ("recover"|"updatefrom"|"help"|"run"|"rmlog") ]]; then
	_error "选项不存在"
	_usage
	exit 1
fi