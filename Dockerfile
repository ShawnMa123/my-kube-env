# 使用 Ubuntu 22.04 作为基础镜像
FROM ubuntu:22.04

# --- 1. 设置工具版本参数 (方便更新) ---
ARG KUBECTL_VERSION=1.29
ARG KREW_VERSION=v0.4.4
ARG HELM_VERSION=v3.15.2
ARG K9S_VERSION=v0.32.5
ARG STERN_VERSION=1.30.0
# ARG POPEYE_VERSION=v0.19.1  <-- 注释掉或删除 Popeye 版本
ARG FZF_VERSION=0.53.0

# 设置 DEBIAN_FRONTEND 避免 apt-get 交互
ENV DEBIAN_FRONTEND=noninteractive

# --- 2. 安装系统依赖 & 基础工具 ---
# 新增: python3-pip, python3-dev, python3-venv 用于 OCI CLI
RUN apt-get update && \
    apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    unzip \
    zsh \
    vim \
    nano \
    python3-pip \
    python3-dev \
    python3-venv \
    ca-certificates \
    gnupg && \
    # 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- 3. 安装 Kubernetes 官方工具 (kubectl) ---
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl

# --- 4. 安装 "黄金套餐" 工具 (已移除 Popeye) ---
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    # Helm
    wget "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" -O helm.tar.gz && tar -zxvf helm.tar.gz && mv "linux-${ARCH}/helm" /usr/local/bin/helm && \
    # k9s
    wget "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" -O k9s.tar.gz && tar -zxvf k9s.tar.gz && mv k9s /usr/local/bin/k9s && \
    # stern
    wget "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" -O stern.tar.gz && tar -zxvf stern.tar.gz && mv stern /usr/local/bin/stern && \
    # fzf
    wget "https://github.com/junegunn/fzf/releases/download/${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz" -O fzf.tar.gz && tar -zxvf fzf.tar.gz && mv fzf /usr/local/bin/fzf && \
    # kubectx & kubens
    wget "https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubectx_v0.9.5_linux_x86_64.tar.gz" -O kubectx.tar.gz && tar -zxvf kubectx.tar.gz && mv kubectx /usr/local/bin/kubectx && \
    wget "https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubens_v0.9.5_linux_x86_64.tar.gz" -O kubens.tar.gz && tar -zxvf kubens.tar.gz && mv kubens /usr/local/bin/kubens && \
    # 清理下载的压缩包
    rm -f *.tar.gz

# --- 5. 创建非 root 用户 ---
RUN useradd -m -s /bin/zsh -u 1001 dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# --- 6. 切换到新用户并配置环境 ---
USER dev
WORKDIR /home/dev

# --- 7. 安装 Oh My Zsh 和插件 ---
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# --- 8. 配置 .zshrc (别名和插件) ---
RUN sed -i 's/plugins=(git)/plugins=(git kubectl helm zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc && \
    echo '\n# --- Custom Aliases ---\n' >> ~/.zshrc && \
    echo "alias k='kubectl'" >> ~/.zshrc && \
    echo "alias kx='kubectx'" >> ~/.zshrc && \
    echo "alias kn='kubens'" >> ~/.zshrc && \
    echo 'source <(kubectl completion zsh)' >> ~/.zshrc && \
    echo 'source <(helm completion zsh)' >> ~/.zshrc

# --- 9. 安装 krew 和 kubelogin ---
RUN ( \
    set -x; cd "$(mktemp -d)" && \
    OS="$(uname | tr '[:upper:]' '[:lower:]')" && \
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" && \
    KREW="krew-${OS}_${ARCH}" && \
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/${KREW}.tar.gz" && \
    tar zxvf "${KREW}.tar.gz" && \
    ./"${KREW}" install krew \
) && \
    echo 'export PATH="${KREW_ROOT:-/home/dev/.krew}/bin:$PATH"' >> ~/.zshrc && \
    /bin/zsh -c "source ~/.zshrc && kubectl krew install oidc-login"

# --- 10. 安装 OCI CLI (为 oulogin) ---
RUN bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- \
    --accept-all-defaults \
    --exec-dir /home/dev/bin \
    --install-dir /home/dev/lib/oci-cli \
    --script-dir /home/dev/bin/oci-cli-scripts && \
    # 确保 OCI CLI 的路径在 .zshrc 中被设置，以便 zsh 登录时能找到它
    echo '\n# Add OCI CLI to PATH' >> ~/.zshrc && \
    echo 'export PATH=/home/dev/bin:$PATH' >> ~/.zshrc

# --- 11. 设置容器默认启动命令 ---
CMD ["/bin/zsh"]