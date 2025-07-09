# 使用 Ubuntu 22.04 作为基础镜像
FROM ubuntu:22.04

# 设置一些参数，方便后续更新版本
ARG KUBECTL_VERSION=1.29
ARG KREW_VERSION=v0.4.4

# 设置环境变量，避免 apt-get 在构建时进行交互
ENV DEBIAN_FRONTEND=noninteractive

# --- 1. 安装系统依赖和基础工具 ---
RUN apt-get update && \
    apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    unzip \
    zsh \
    ca-certificates \
    gnupg && \
    # 清理 apt 缓存，减小镜像体积
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- 2. 安装 kubectl ---
# 添加 Kubernetes 的官方 GPG key
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# 添加 Kubernetes 的 apt 仓库
RUN echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
# 更新 apt 包索引并安装 kubectl
RUN apt-get update && apt-get install -y kubectl

# --- 3. 创建一个非 root 用户 ---
# 创建一个名为 dev 的用户，并将其 shell 设置为 zsh
RUN useradd -m -s /bin/zsh -u 1001 dev
# 允许 dev 用户无密码使用 sudo，方便在容器内调试
RUN echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# --- 4. 切换到新用户并配置环境 ---
USER dev
WORKDIR /home/dev

# --- 5. 安装 Oh My Zsh 和常用插件 ---
# 以非交互模式安装 Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
# 安装 zsh-autosuggestions 插件 (灰色提示历史命令)
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
# 安装 zsh-syntax-highlighting 插件 (命令语法高亮)
RUN git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# --- 6. 配置 .zshrc 启用插件 ---
# 使用 sed 命令修改 .zshrc 文件，将默认的 git 插件扩展为我们需要的插件列表
RUN sed -i 's/plugins=(git)/plugins=(git kubectl zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# --- 7. 安装 krew (kubectl 插件管理器) 和 kubelogin ---
# 安装 krew
RUN ( \
    set -x; cd "$(mktemp -d)" && \
    OS="$(uname | tr '[:upper:]' '[:lower:]')" && \
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" && \
    KREW="krew-${OS}_${ARCH}" && \
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/${KREW}.tar.gz" && \
    tar zxvf "${KREW}.tar.gz" && \
    ./"${KREW}" install krew \
)
# 将 krew 添加到 PATH
RUN echo 'export PATH="${KREW_ROOT:-/home/dev/.krew}/bin:$PATH"' >> ~/.zshrc

# 使用 krew 安装 kubelogin 插件
# 注意: 我们需要 source .zshrc 来让 krew 命令生效
RUN /bin/zsh -c "source ~/.zshrc && kubectl krew install oidc-login"

# --- 8. 设置容器启动命令 ---
# 启动时默认进入 zsh
CMD ["/bin/zsh"]