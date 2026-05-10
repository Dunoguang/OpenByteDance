#!/bin/bash

# 基础镜像构建：docker buildx build --platform linux/amd64 -t fpa-sandbox-base:{version} -f Dockerfile.base . --load

# 默认参数
DO_TAG_PUSH=true
TEST_MODE=false
VOlCES_REGISTRY="flow-fpa-cn-beijing.cr.volces.com/fpa-vm"
ICM_REGISTRY="hub.byted.org/flow_mcp"
IMAGE_NAME="ci_base"

# 显示帮助信息
show_help() {
    echo "用法: $0 [版本号] [选项]"
    echo ""
    echo "参数:"
    echo "  版本号          版本号参数（test模式下可选，会自动递增）"
    echo ""
    echo "选项:"
    echo "  --no-push       只构建镜像，不执行tag和push操作"
    echo "  --test          测试模式：跳过git检查，版本号自动加.test后缀"
    echo "  --registry URL  指定镜像仓库地址 (默认: flow-fpa-cn-beijing.cr.volces.com/fpa-vm)"
    echo "  -h, --help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 1.0.0                    # 构建并推送镜像"
    echo "  $0 1.0.0 --no-push          # 只构建镜像，不推送"
    echo "  $0 1.0.0 --test             # 测试模式：跳过git检查，版本号变为1.0.0.test"
    echo "  $0 --test                   # 测试模式：自动递增版本号"
    echo "  $0 1.0.0 --registry my.registry.com/repo  # 使用自定义仓库地址"
}

# 获取本地最新版本号并递增小版本号
# 获取本地最新版本号并递增小版本号
get_next_version() {
    # 获取本地所有镜像的标签，过滤掉带test的版本
    local latest_version=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep $IMAGE_NAME | grep -v "<none>" | grep -v "\.test" | head -1 | cut -d':' -f2 | cut -d'.' -f1-3)
    
    if [ -z "$latest_version" ]; then
        # 如果没有找到本地镜像，使用默认版本
        echo "0.0.0"
        return
    fi
    
    # 解析版本号 (假设格式为 x.y.z)
    local major=$(echo $latest_version | cut -d'.' -f1)
    local minor=$(echo $latest_version | cut -d'.' -f2)
    local patch=$(echo $latest_version | cut -d'.' -f3)
    
    # 递增小版本号
    patch=$((patch + 1))
    
    echo "${major}.${minor}.${patch}"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-push)
            DO_TAG_PUSH=false
            shift
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --registry)
            VOlCES_REGISTRY="$2"
            shift 2
            ;;
        -*)
            echo "错误: 未知选项 $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo "错误: 多余的参数 $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查版本号参数
if [ -z "$VERSION" ]; then
    if [ "$TEST_MODE" = true ]; then
        # test模式下自动获取下一个版本号
        VERSION=$(get_next_version)
        DO_TAG_PUSH=false
        echo "🔄 test模式：自动使用版本号 ${VERSION}"
    else
        echo "错误: 请提供版本号参数"
        show_help
        exit 1
    fi
fi

# 如果是测试模式，给版本号加上.test后缀
if [ "$TEST_MODE" = true ]; then
    VERSION="${VERSION}.test"
fi

# 检查git工作目录是否干净（测试模式下跳过检查）
if [ "$TEST_MODE" = false ]; then
    echo "🔍 检查git工作目录状态..."
    if ! git diff-index --quiet HEAD --; then
        echo "❌ 错误: git工作目录有未提交的更改"
        echo "请先提交或暂存所有更改后再构建镜像:"
        echo "  git add ."
        echo "  git commit -m 'your commit message'"
        echo ""
        echo "或者使用 --test 选项进入测试模式"
        echo "当前未提交的文件:"
        git status --porcelain
        exit 1
    fi

    # 检查是否有未跟踪的文件
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "⚠️  警告: 发现未跟踪的文件"
        echo "以下文件未被git跟踪:"
        git ls-files --others --exclude-standard
        echo ""
        read -p "是否继续构建? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "构建已取消"
            exit 1
        fi
    fi

    echo "✅ git工作目录状态检查通过"
else
    echo "🧪 测试模式：跳过git状态检查"
fi
echo ""

# 获取最新的git commit ID的前10位
GIT_COMMIT=$(git rev-parse --short=10 HEAD)

# 检查git命令是否成功执行
if [ $? -ne 0 ]; then
    echo "错误: 无法获取git commit ID，请确保当前目录是一个git仓库"
    exit 1
fi

# 构建镜像标签
LOCAL_IMAGE_TAG="${IMAGE_NAME}:${VERSION}.${GIT_COMMIT}"
VOlCES_IMAGE_TAG="${VOlCES_REGISTRY}/${IMAGE_NAME}:${VERSION}.${GIT_COMMIT}"
ICM_IMAGE_TAG="${ICM_REGISTRY}/${IMAGE_NAME}:${VERSION}.${GIT_COMMIT}"


echo "开始构建Docker镜像..."
echo "版本号: ${VERSION}"
echo "Git Commit ID: ${GIT_COMMIT}"
echo "本地镜像标签: ${LOCAL_IMAGE_TAG}"
if [ "$DO_TAG_PUSH" = true ]; then
    echo "火山镜像标签: ${VOlCES_IMAGE_TAG}"
    echo "icm镜像标签: ${ICM_IMAGE_TAG}"
fi
echo ""

# 执行docker buildx build命令
echo "🔨 构建镜像..."
docker buildx build --platform linux/amd64 -t "${LOCAL_IMAGE_TAG}" --file Dockerfile_base . --load

# 检查构建是否成功
if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Docker镜像构建失败!"
    exit 1
fi

echo "✅ Docker镜像构建成功!"

# 如果需要tag和push
if [ "$DO_TAG_PUSH" = true ]; then
    echo ""
    echo "🏷️  为镜像添加远程标签..."
    docker tag "${LOCAL_IMAGE_TAG}" "${VOlCES_IMAGE_TAG}"
    docker tag "${LOCAL_IMAGE_TAG}" "${ICM_IMAGE_TAG}"

    if [ $? -ne 0 ]; then
        echo "❌ 镜像标签添加失败!"
        exit 1
    fi
    
    echo "✅ 镜像标签添加成功!"
    
    echo ""
    echo "📤 推送镜像到远程仓库..."
    docker push "${VOlCES_IMAGE_TAG}"
    docker push "${ICM_IMAGE_TAG}"

    if [ $? -ne 0 ]; then
        echo "❌ 镜像推送失败!"
        exit 1
    fi
    
    echo "✅ 镜像推送成功!"
    echo ""
    echo "🎉 完成! 镜像已成功构建并推送:"
    echo "   本地标签: ${LOCAL_IMAGE_TAG}"
    echo "   火山标签: ${VOlCES_IMAGE_TAG}"
    echo "   icm标签: ${ICM_IMAGE_TAG}"
else
    echo ""
    echo "🎉 完成! 镜像已成功构建:"
    echo "   本地标签: ${LOCAL_IMAGE_TAG}"
    echo "   (跳过tag和push操作)"
fi