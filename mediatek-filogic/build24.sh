#!/bin/bash
source shell/custom-packages.sh
source shell/switch_repository.sh
# 该文件实际为imagebuilder容器内的build.sh

#echo "✅ 你选择了第三方软件包：$CUSTOM_PACKAGES"
# 下载 run 文件仓库
echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

# 拷贝 run/arm64 下所有 run 文件和ipk文件 到 extra-packages 目录
mkdir -p /home/build/immortalwrt/extra-packages
cp -rf /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

echo"✅ 运行文件已复制到extra-packages："
ls -lh /home/build/immortalwrt/extra-packages/*.run 2>/dev/null

# 解压并拷贝ipk到packages目录
sh shell/prepare-packages.sh
ls -lah /home/build/immortalwrt/packages/

# 添加架构优先级信息（确保文件存在）
if [ -f repositories.conf ]; then
  sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf
fi

# yml 传入的路由器型号 PROFILE
echo"构建配置文件：$PROFILE"
echo"包含Docker：$INCLUDE_DOCKER"
echo "Create pppoe-settings"

# 创建配置目录
mkdir -p /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件（安全写入，避免空值破环格式）
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE:-no}
pppoe_account=${PPPOE_ACCOUNT:-}
pppoe_password=${PPPOE_PASSWORD:-}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建过程..."

# 定义所需安装的包列表
PACKAGES=""
PACKAGES+=" curl luci luci-i18n-base-zh-cn"
PACKAGES+=" luci-i18n-firewall-zh-cn"
PACKAGES+=" luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES+=" luci-i18n-package-manager-zh-cn"
PACKAGES+=" luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES+=" luci-i18n-filemanager-zh-cn"
PACKAGES+=" luci-app-openclash"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"

# 第三方软件包合并
if [[ "$PROFILE" == "glinet_gl-axt1800" || "$PROFILE" == "glinet_gl-ax1800" ]]; then
    echo "Model:$PROFILE not support third-parted packages"
    PACKAGES+=" -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    echo "Other Model:$PROFILE"
    PACKAGES+=" ${CUSTOM_PACKAGES}"
fi

# 判断是否需要编译 Docker 插件
if [[ "$INCLUDE_DOCKER" == "yes" ]]; then
    PACKAGES+=" luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p /home/build/immortalwrt/files/etc/openclash/core

    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -q --timeout=10 -O- "$META_URL" | tar xOvz > /home/build/immortalwrt/files/etc/openclash/core/clash_meta
    chmod +x /home/build/immortalwrt/files/etc/openclash/core/clash_meta

    # Download GeoIP and GeoSite
    wget -q --timeout=10 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O /home/build/immortalwrt/files/etc/openclash/GeoIP.dat
    wget -q --timeout=10 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O /home/build/immortalwrt/files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
