#!/bin/bash

set -e -o pipefail

export USE_SUDO=

export BIN_PATH=/usr/local/bin
export PKG_ARCH=
export OS_ARCH=
export COMPLETION_FOLDER="$HOME/completions"
mkdir -p $COMPLETION_FOLDER
_bashrc=$HOME/.bashrc

export _CURL="curl -sS"
export _WGET="wget -q --show-progress"

log_red() {
  echo -e "\e[31m$1\e[0m"
}

add_to_profile() {
  section=$1
  code=$2

  grep "#$section" $_bashrc && (log_red "found section $section, replacing" && sed -i "/#$section/,/#\/$section/d" $_bashrc && sed -i '/^$/N;/\n$/s/\n//;P;D' $_bashrc) || echo -n

  echo "" >>$_bashrc
  echo "#$section" >>$_bashrc
  echo "$code" >>$_bashrc
  echo "#/$section" >>$_bashrc
  # source $_bashrc
}

function proxy() {
  $_CURL google.de || log_red "Proxy needed? set HTTP_PROXY"
  sleep 5
  if [ -n "$HTTP_PROXY" ]; then
    log_red "using proxy $HTTP_PROXY"
    export https_proxy=$HTTP_PROXY
    export http_proxy=$HTTP_PROXY
    export HTTP_PROXY=$HTTP_PROXY
    export HTTPS_PROXY=$HTTP_PROXY

    add_to_profile proxy "export https_proxy=$HTTP_PROXY
export http_proxy=$HTTP_PROXY
export HTTP_PROXY=$HTTP_PROXY
export HTTPS_PROXY=$HTTP_PROXY"
    $USE_SUDO echo "Acquire::http::Proxy \"$HTTP_PROXY\";
Acquire::https::Proxy \"$HTTP_PROXY\";" | $USE_SUDO tee /etc/apt/apt.conf
  fi
}

function prepare() {
  sudo -v && export USE_SUDO="sudo" || log_red "no sudo found, continuing without"

  export OS_ARCH=$(uname -m)
  if [[ "$OS_ARCH" == "x86_64" ]]; then
    export PKG_ARCH=amd64
  fi
  if [[ "$OS_ARCH" == "aarch64" ]]; then
    export PKG_ARCH=arm64
  fi

  termux-info && export TERMUX=true || export TERMUX=false
  echo TERMUX enabled: $TERMUX
  if [[ "$TERMUX" == "true" ]]; then
    :
    termux_install
  fi

  # proxy
  # rm -f /etc/apt/apt.conf.d/docker-clean # enable shell completion for apt in ubuntu docker image
  # add_to_profile xdg 'XDG_CONFIG_HOME="$HOME/.config"'

  export TZ=Europe/Berlin
  export DEBIAN_FRONTEND=noninteractive

  $USE_SUDO apt update
  $USE_SUDO apt install -y curl wget git bash-completion jq
  $USE_SUDO apt upgrade -y

  source $HOME/.workbench || echo "no customization found"
}

function terraform_install() {
  log_red "Installing terraform"

  VERSION=$($_CURL https://api.github.com/repos/hashicorp/terraform/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$(terraform version | sed -n 's/^Terraform v//p')" == "$VERSION" ]]; then
    echo "terraform $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://releases.hashicorp.com/terraform/$VERSION/terraform_${VERSION}_linux_${PKG_ARCH}.zip -O "$tmpdir/terraform.zip"
    unzip "$tmpdir/terraform.zip" -d "$tmpdir"
    $USE_SUDO mv -f "$tmpdir/terraform" $BIN_PATH
    rm -rf "$tmpdir"
    if [[ "$TERMUX" == "true" ]]; then
      pushd $PREFIX/bin
      mv terraform _terraform
      echo "#!$PREFIX/bin/bash
$PROOT_DNS_CERTS $PREFIX/bin/_terraform \$@" >terraform
      chmod +x terraform
      popd
    fi
  fi

  terraform -install-autocomplete || echo "probably already added terraform autoinstall"

  if [[ "$TERMUX" == "true" ]]; then
    add_to_profile terraform 'complete -C $PREFIX/bin/terraform tf
complete -C $PREFIX/bin/terraform terraform
alias tf="terraform"
alias tfi="terraform init"
alias tfp="terraform plan"
alias tfa="terraform apply"
alias tfaa="terraform apply -auto-approve"
alias tfd="terraform destroy"
alias tfda="terraform destroy -auto-approve"'"
export PASSWORD=\$(bws secret list | yq e '.[] | select(.key == \"password\") | .value')
export TF_VAR_password=\$PASSWORD
export TF_VAR_bitwarden_access_token=\$BWS_ACCESS_TOKEN
export TF_VAR_home=$HOME
export TF_VAR_prefix=$PREFIX
export TF_VAR_portainer_endpoint=\$TF_VAR_portainer_endpoint" # -> set via .secure_vars
  else
    add_to_profile terraform 'complete -C /usr/bin/terraform tf
complete -C /usr/bin/terraform terraform
alias tf="terraform"
alias tfi="terraform init"
alias tfp="terraform plan"
alias tfa="terraform apply"
alias tfaa="terraform apply -auto-approve"
alias tfd="terraform destroy"
alias tfda="terraform destroy -auto-approve"'"
export PASSWORD=\$(bws secret list | yq e '.[] | select(.key == \"password\") | .value')
export TF_VAR_password=\$PASSWORD
export TF_VAR_bitwarden_access_token=\$BWS_ACCESS_TOKEN
export TF_VAR_portainer_endpoint=\$TF_VAR_portainer_endpoint" # -> set via .secure_vars
  fi

  terraform --version
}

function kustomize_install() {
  log_red "Installing kustomize"

  TAG=$($_CURL https://api.github.com/repos/kubernetes-sigs/kustomize/releases | jq -r '[.[] | select(.prerelease == false)] | [.[] | select(.tag_name | contains("kustomize"))] | .[0].tag_name')
  if [[ "$(kustomize version --short 2>/dev/null | sed 's/.*{\([^ ]*\).*/\1/')" == "$TAG" ]]; then
    echo "kustomize $TAG already installed, skipping download"
  else
    if [[ "$TERMUX" == "true" ]]; then
      git clone https://github.com/kubernetes-sigs/kustomize.git
      pushd kustomize
      git checkout $TAG
      make kustomize
      popd
      rm -rf kustomize
    else
      $_CURL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -
      $USE_SUDO mv -f kustomize $BIN_PATH
    fi
  fi
  kustomize completion bash >completion_kustomize
  $USE_SUDO mv -f completion_kustomize $COMPLETION_FOLDER/kustomize
  add_to_profile kustomize 'source'" $COMPLETION_FOLDER/kustomize"' 
alias touchk="touch kustomization.yaml && (kustomize edit remove resource \$(yq '"'.resources[]'"' kustomization.yaml) 2> /dev/null || \:) && kustomize edit add resource *.yaml && kustomize edit add resource */ 2>/dev/null || \:"'
  kustomize version
}

function helm_install() {
  log_red "Installing helm"

  if [[ "$TERMUX" == "true" ]]; then
    apt install -y helm
  else
    $_WGET https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    $USE_SUDO chmod +x get-helm-3
    ./get-helm-3
    $USE_SUDO rm get-helm-3
  fi

  helm completion bash >completion_helm
  $USE_SUDO mv -f completion_helm $COMPLETION_FOLDER/helm
  add_to_profile helm "source $COMPLETION_FOLDER/helm"
  helm version
}

function kubectl_install() {
  log_red "Installing kubectl"

  if [[ "$TERMUX" == "true" ]]; then
    apt install -y kubectl
  else
    VERSION=$(curl -LsS https://dl.k8s.io/release/stable.txt)
    if [[ "v$(kubectl version --client --output=json 2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/v//g')" == "$VERSION" ]]; then
      echo "kubectl $VERSION already installed, skipping download"
    else
      tmpdir="$(mktemp -d)"
      wget https://dl.k8s.io/release/$VERSION/bin/linux/$PKG_ARCH/kubectl -O "$tmpdir/kubectl"
      chmod +x "$tmpdir/kubectl"
      $USE_SUDO mv -f "$tmpdir/kubectl" $BIN_PATH
      rm -rf "$tmpdir"
    fi
  fi

  kubectl completion bash >completion_kubectl

  section=custom_kubectl_completion
  code='\
    __kubectl_debug "=========== starting alias manipulation ==========="\
    __kubectl_debug "in prev '"'"'${prev}'"'"' words '"'"'${words[*]}'"'"', cword '"'"'$cword'"'"'"\
    if [[ "${words[0]}" == "k" ]] ; then\
        __kubectl_debug  "called k"\
        words=("kubectl" "${words[@]:1}")\
        prev="kubectl"\
    elif [[ "${words[0]}" == "ka" ]] ; then\
        __kubectl_debug  "called ka"\
        words=("kubectl" "apply" "${words[@]:1}")\
        cword=$(($cword+1))\
        prev="apply"\
    elif [[ "${words[0]}" == "kak" ]] ; then\
        __kubectl_debug  "called kak"\
        words=("kubectl" "apply" "-k" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="-k"\
    elif [[ "${words[0]}" == "kaf" ]] ; then\
        __kubectl_debug  "called kaf"\
        words=("kubectl" "apply" "-f" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="-f"\
    elif [[ "${words[0]}" == "krm" ]] ; then\
        __kubectl_debug  "called krm"\
        words=("kubectl" "delete" "${words[@]:1}")\
        cword=$(($cword+1))\
        prev="delete"\
    elif [[ "${words[0]}" == "krma" ]] ; then\
        __kubectl_debug  "called krma"\
        words=("kubectl" "delete" "--all" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="--all"\
    elif [[ "${words[0]}" == "kg" ]] ; then\
        __kubectl_debug  "called kg"\
        words=("kubectl" "get" "${words[@]:1}")\
        cword=$(($cword+1))\
        prev="get"\
    elif [[ "${words[0]}" == "kgp" ]] ; then\
        __kubectl_debug  "called kgp"\
        words=("kubectl" "get" "pods" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="get"\
    elif [[ "${words[0]}" == "krmk" ]] ; then\
        __kubectl_debug  "called krmk"\
        words=("kubectl" "delete" "-k" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="-k"\
    elif [[ "${words[0]}" == "krmf" ]] ; then\
        __kubectl_debug  "called krmf"\
        words=("kubectl" "delete" "-f" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="-f"\
    elif [[ "${words[0]}" == "kcns" ]] ; then\
        __kubectl_debug  "called kcns"\
        words=("kubectl" "create" "ns" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="ns"\
    else \
        __kubectl_debug "${words[0]} is not a known alias => not manipulating"\
        unmanipulated=un\
    fi\
    __kubectl_debug "${unmanipulated}manipulated prev '"'"'${prev}'"'"' words '"'"'${words[*]}'"'"', cword '"'"'$cword'"'"'"\
'

  grep "#$section" completion_kubectl && (echo "found section $section, replacing" && sed -i "/#$section/,/#\/$section/d" completion_kubectl && sed -i '/^$/N;/\n$/s/\n//;P;D' completion_kubectl) || echo -n
  sed -i '/__kubectl_debug "========= starting completion logic =========="/a'"\
#$section$code#\/$section" completion_kubectl
  sed -i 's/__kubectl_debug "========= starting completion logic =========="//g' completion_kubectl
  sed -i "/#\/$section/a"'\
    __kubectl_debug "========= starting completion logic =========="' completion_kubectl
  $USE_SUDO mv -f completion_kubectl $COMPLETION_FOLDER/kubectl

  echo "source $COMPLETION_FOLDER/kubectl"'
alias k=kubectl
alias kake="kustomize build --enable-helm . | kubectl apply -f -"
complete -F __start_kubectl k
complete -F __start_kubectl ka
alias ka="kubectl apply"
complete -F __start_kubectl kak
alias kak="kubectl apply -k"
complete -F __start_kubectl kaf
alias kaf="kubectl apply -f"
complete -F __start_kubectl krm
alias krm="kubectl delete"
complete -F __start_kubectl krma
alias krma="kubectl delete --all"
complete -F __start_kubectl kg
alias kg="kubectl get"
complete -F __start_kubectl kgp
alias kgp="kubectl get pods"
complete -F __start_kubectl krmk
alias krmk="kubectl delete -k"
complete -F __start_kubectl krmf
alias krmf="kubectl delete -f"
complete -F __start_kubectl kcns
alias kcns="kubectl create ns"
complete -F __start_kubectl kng
alias kng="kubectl neat get"
' >$HOME/.kubectl_aliases # somehow completion only works when it's sourced last

  kubectl version --client
}

function oc_install() {
  log_red "Installing oc"

  if [[ "$TERMUX" == "true" ]]; then
    log_red "skipping"
    return
  fi

  # version check pain in the ass...
  tmpdir="$(mktemp -d)"
  $_WGET https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -O "$tmpdir/oc.tar.gz"
  tar -xvf "$tmpdir/oc.tar.gz" -C "$tmpdir"
  $USE_SUDO mv "$tmpdir/oc" $BIN_PATH
  rm -rf "$tmpdir"

  oc completion bash >completion_oc
  $USE_SUDO mv -f completion_oc $COMPLETION_FOLDER/oc
  add_to_profile oc "source $COMPLETION_FOLDER/oc
alias o=oc"
  oc version --client
}

function krew_install() {
  log_red "Installing krew"

  if [[ "$TERMUX" == "true" ]]; then
    log_red "skipping"
    return
  fi

  VERSION=$($_CURL https://api.github.com/repos/kubernetes-sigs/krew/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$($(find "$HOME" -iname krew -type f 2>/dev/null | head -1) version 2>/dev/null | sed -n 's/GitTag[[:space:]]*v//p')" == "$VERSION" ]]; then
    echo "krew $VERSION already installed, skipping download"
  else
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    KREW="krew-${OS}_${PKG_ARCH}"
    tmpdir="$(mktemp -d)"
    $_WGET "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" -O "$tmpdir/krew.tar.gz"
    tar -xvf "$tmpdir/krew.tar.gz" -C "$tmpdir"
    "$tmpdir/${KREW}" install krew
    rm -rf "$tmpdir"
  fi

  add_to_profile krew 'export PATH="$PATH:${KREW_ROOT:-$HOME/.krew}/bin"'
  # completion not yet working: https://github.com/kubernetes-sigs/krew/issues/812
  export PATH="$PATH:${KREW_ROOT:-$HOME/.krew}/bin"
  export KREW_BIN="$(find "$HOME" -iname krew -type f 2>/dev/null | head -1)"
  $KREW_BIN version
}

function kubectx_install() {
  log_red "Installing kubectx"

  # skip version check, seems to very rarely get updates but not releases..just use master as it's just a bash script
  git clone https://github.com/ahmetb/kubectx.git
  pushd kubectx
  $USE_SUDO mv -f kubectx $BIN_PATH
  $USE_SUDO mv -f kubens $BIN_PATH
  popd
  rm -rf kubectx

  if [[ "$TERMUX" == "true" ]]; then
    :
  else
    "$KREW_BIN" install ctx
    "$KREW_BIN" install ns
  fi

  add_to_profile kubectx 'alias kctx="kubectx"
alias kns="kubens"'
  kubectx --help
  kubens --help
}

function netshoot_install() {
  log_red "Installing netshoot"

  if command -v netshoot >/dev/null 2>&1; then
    echo "netshoot $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/nilic/kubectl-netshoot/releases/download/v0.1.0/kubectl-netshoot_v0.1.0_linux_$PKG_ARCH.tar.gz -O "$tmpdir/netshoot.tar.gz"
    tar -xvf "$tmpdir/netshoot.tar.gz" -C "$tmpdir"
    $USE_SUDO mv -f "$tmpdir/kubectl-netshoot" $BIN_PATH/netshoot
    rm -rf "$tmpdir"
    if [[ "$TERMUX" == "true" ]]; then
      :
    else
      "$KREW_BIN" index add netshoot https://github.com/nilic/kubectl-netshoot.git || echo "index already added"
      "$KREW_BIN" install netshoot/netshoot
    fi
  fi

  netshoot completion bash >completion_netshoot
  $USE_SUDO mv -f completion_netshoot $COMPLETION_FOLDER/netshoot
  add_to_profile netshoot "alias netshoot='k netshoot run tmp'
source $COMPLETION_FOLDER/netshoot"
  netshoot version
}

function k9s_install() {
  log_red "Installing k9s"

  if [[ "$TERMUX" == "true" ]]; then
    apt install -y k9s
  else
    VERSION=$($_CURL https://api.github.com/repos/derailed/k9s/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
    if [[ "$(k9s version 2>/dev/null | sed -n 's/^Version *//p')" == "$VERSION" ]]; then
      echo "k9s $VERSION already installed, skipping download"
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://github.com/derailed/k9s/releases/latest/download/k9s_linux_$PKG_ARCH.deb -O "$tmpdir/k9s.deb"
      $USE_SUDO cp "$tmpdir/k9s.deb" /tmp/
      $USE_SUDO apt install -y --fix-missing /tmp/k9s.deb
      rm -rf "$tmpdir"
    fi
  fi

  k9s completion bash >completion_k9s
  $USE_SUDO mv -f completion_k9s $COMPLETION_FOLDER/k9s
  add_to_profile k9s "source $COMPLETION_FOLDER/k9s
alias kd=k9s"

  mkdir -p $HOME/.config/k9s

  echo 'k9s:
  liveViewAutoRefresh: true
  refreshRate: 1
  reactive: true
  noIcons: false' >$HOME/.config/k9s/config.yaml

  echo 'hotKeys:
  F1:
    shortCut: F1
    description: ns
    command: ns
  F2:
    shortCut: F2
    description: pods
    command: pods
  F3:
    shortCut: F3
    description: deployments
    command: deployments
  F4:
    shortCut: F4
    description: service
    command: service
  F5:
    shortCut: F5
    description: ingress
    command: ingress
  F6:
    shortCut: F6
    description: secrets
    command: secrets
  F7:
    shortCut: F7
    description: configmaps
    command: configmaps
  F8:
    shortCut: F8
    description: application
    command: application
  F12:
    shortCut: F12
    description: context
    command: context' >$HOME/.config/k9s/hotkeys.yaml

  k9s version
}

function go_install() {
  log_red "Installing go"

  export GO_HOME=$HOME/go
  if [[ "$TERMUX" == "true" ]]; then
    apt install -y golang
    export GO_PATH=$PREFIX/local/go
  else
    export GO_PATH_BASE=/usr/local
    export GO_PATH=$GO_PATH_BASE/go
    GO_VERSION=$($_CURL https://go.dev/VERSION?m=text | cut -d' ' -f3 | tr -d 'go')
    if [[ "$(go version | sed 's/.*go\([0-9.]*\).*/\1/')" == "$GO_VERSION" ]]; then
      echo "go $GO_VERSION already installed, skipping download"
    else
      go version >/dev/null && log_red "Found pre-existing go version. reinstalling..." && $USE_SUDO rm -rf $GO_PATH
      tmpdir="$(mktemp -d)"
      $_WGET https://go.dev/dl/go$GO_VERSION.linux-$PKG_ARCH.tar.gz -O "$tmpdir/go.tar.gz"
      $USE_SUDO tar -C $GO_PATH_BASE -xzf "$tmpdir/go.tar.gz"
      rm -rf "$tmpdir"
    fi
  fi

  add_to_profile go 'export PATH="$PATH:'$GO_PATH/bin':'$GO_HOME/bin'"'
  export PATH="$PATH:$GO_PATH/bin:$GO_HOME/bin"
  go version
}

function kubecolor_install() {
  log_red "Installing kubecolor"

  go install github.com/kubecolor/kubecolor@latest

  add_to_profile kubecolor "alias kc=kubecolor
  alias kubectl=kubecolor
complete -F __start_kubectl kubecolor"
  kubecolor version --client
}

function docker_install() {
  log_red "Installing docker"

  if [[ "$TERMUX" == "true" ]]; then
    VERSION=$($_CURL https://api.github.com/repos/moby/buildkit/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
    if [[ "$(buildctl version --remote=false 2>/dev/null | sed -n 's/^.*version: //p')" == "$VERSION" ]]; then
      echo "buildctl $VERSION already installed, skipping download"
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://github.com/moby/buildkit/releases/latest/download/buildkit-v$VERSION.linux-$PKG_ARCH.tar.gz -O "$tmpdir/buildkit.tar.gz"
      tar -xvf "$tmpdir/buildkit.tar.gz" -C "$tmpdir"
      mv -f "$tmpdir/bin/buildctl" $BIN_PATH
      rm -rf "$tmpdir"
    fi

    add_to_profile docker 'function dbt () {
  "$PROOT_DNS_CERTS buildctl build --frontend dockerfile.v0 --local context=. --local dockerfile=.
}"'
    return
  fi

  $USE_SUDO apt -y install docker.io docker-buildx

  docker completion bash >completion_docker
  $USE_SUDO mv -f completion_docker $COMPLETION_FOLDER/docker
  add_to_profile docker 'function run-it() {
  docker run -v "${PWD}:/pwd" "$1" /bin/bash -c : || ( echo fallback to sh && docker run -it -v "${PWD}:/pwd" "$1" /bin/sh ) && docker run -it -v "${PWD}:/pwd" "$1" /bin/bash
}
export -f run-it
alias rit=run-it
alias dbt="docker build . -t"'"
source $COMPLETION_FOLDER/docker
complete -F __start_docker docker"
  docker --version
}

function kubectl_neat_install() {
  log_red "Installing kubectl-neat"

  if [[ "$TERMUX" == "true" ]]; then
    VERSION=$($_CURL https://api.github.com/repos/itaysk/kubectl-neat/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
    if [[ "$(kubectl-neat version 2>/dev/null | sed 's/.* //')" == "$VERSION" ]]; then
      echo "kubectl-neat $VERSION already installed, skipping download"
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://github.com/itaysk/kubectl-neat/releases/latest/download/kubectl-neat_linux_$PKG_ARCH.tar.gz -O "$tmpdir/kubectl-neat.tar.gz"
      tar -xvf "$tmpdir/kubectl-neat.tar.gz" -C "$tmpdir"
      mv -f "$tmpdir/kubectl-neat" $BIN_PATH
      rm -rf "$tmpdir"
    fi
  else
    "$KREW_BIN" install neat
  fi

  add_to_profile neat "alias kn='kubectl-neat'"
  kubectl-neat version
}

function kyverno_install() {
  log_red "Installing kyverno"

  VERSION=$($_CURL https://api.github.com/repos/kyverno/kyverno/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  F_ARCH=$OS_ARCH
  if [[ "$F_ARCH" == "aarch64" ]]; then
    # kyverno using arch inconsistently with other tools..
    F_ARCH=$PKG_ARCH
  fi
  if [[ "$(kyverno version 2>/dev/null | sed -n 's/^Version: //p')" == "$VERSION" ]]; then
    echo "kyverno $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/kyverno/kyverno/releases/download/v$VERSION/kyverno-cli_v${VERSION}_linux_${F_ARCH}.tar.gz -O "$tmpdir/kyverno.tar.gz"
    tar -xvf "$tmpdir/kyverno.tar.gz" -C "$tmpdir"
    $USE_SUDO mv "$tmpdir/kyverno" $BIN_PATH
    rm -rf "$tmpdir"
  fi

  kyverno completion bash >completion_kyverno
  $USE_SUDO mv -f completion_kyverno $COMPLETION_FOLDER/kyverno
  add_to_profile kyverno "source $COMPLETION_FOLDER/kyverno"
  kyverno version
}

function istioctl_install() {
  log_red "Installing istioctl"

  VERSION=$($_CURL https://api.github.com/repos/istio/istio/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$(istioctl version --remote=false 2>/dev/null | sed -n 's/^.*version: //p')" == "$VERSION" ]]; then
    echo "istioctl $VERSION already installed, skipping download"
  else
    $_CURL -L https://istio.io/downloadIstio | sh -
    $USE_SUDO mv istio-*/bin/istioctl $BIN_PATH
    rm -rf istio-*
  fi

  istioctl completion bash >completion_istioctl
  $USE_SUDO mv -f completion_istioctl $COMPLETION_FOLDER/istioctl
  add_to_profile istioctl "source $COMPLETION_FOLDER/istioctl"
  istioctl version --remote=false
}

function mc_install() {
  log_red "Installing mc"

  VERSION=$($_CURL https://api.github.com/repos/minio/mc/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name')
  if [[ "$(mc --version 2>/dev/null | sed -n 's/^mc version \(.*\) (.*)/\1/p')" == "$VERSION" ]]; then
    echo "mc $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://dl.min.io/client/mc/release/linux-$PKG_ARCH/mc -O "$tmpdir/mc"
    chmod +x "$tmpdir/mc"
    $USE_SUDO mv "$tmpdir/mc" $BIN_PATH
    rm -rf "$tmpdir"
  fi

  export SHELL=/bin/bash # ensure shell for docker
  mc --autocompletion
  mc --version
}

function yq_install() {
  log_red "Installing yq"

  VERSION=$($_CURL https://api.github.com/repos/mikefarah/yq/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$(yq --version 2>/dev/null | sed -n 's/^.*version v//p')" == "$VERSION" ]]; then
    echo "yq $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$PKG_ARCH -O "$tmpdir/yq"
    chmod +x "$tmpdir/yq"
    $USE_SUDO mv -f "$tmpdir/yq" $BIN_PATH
    rm -rf "$tmpdir"
  fi

  yq completion bash >completion_yq
  $USE_SUDO mv -f completion_yq $COMPLETION_FOLDER/yq
  add_to_profile yq "source $COMPLETION_FOLDER/yq"
  yq --version
}

function ccat_install() {
  log_red "Installing ccat"

  VERSION=$($_CURL https://api.github.com/repos/batmac/ccat/releases | jq -r '.[0].tag_name' | sed 's/v//g')
  if [[ "$(ccat --version 2>/dev/null | sed 's/.*v\([0-9.]*\).*/\1/')" == "$VERSION" ]]; then
    echo "ccat $VERSION already installed, skipping build"
  else
    if [[ "$TERMUX" == "true" ]]; then
      git clone https://github.com/batmac/ccat.git
      pushd ccat
      git checkout v$VERSION
      sed -i 's/var Default = BuildDefaultAndTest/var Default = BuildDefault/g' magefiles/magefile.go
      make build
      mv -f ccat $BIN_PATH
      popd
      rm -rf ccat
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://github.com/batmac/ccat/releases/download/v$VERSION/ccat-$VERSION-linux-$PKG_ARCH.tar.gz -O "$tmpdir/ccat.tar.gz"
      tar -xvf "$tmpdir/ccat.tar.gz" -C "$tmpdir"
      $USE_SUDO mv -f "$tmpdir/ccat" $BIN_PATH
      rm -rf "$tmpdir"
    fi
  fi

  add_to_profile ccat "alias cat=ccat
alias _cat=$BIN_PATH/cat"
  ccat --version
}

function talosctl_install() {
  log_red "Installing talosctl"

  if [[ "$TERMUX" == "true" ]]; then
    MODIFIER="proot -b $PREFIX/tmp:/tmp"
  else
    MODIFIER="$USE_SUDO"
  fi

  VERSION=$($_CURL https://api.github.com/repos/siderolabs/talos/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$(talosctl version --client 2>/dev/null | sed -n 's/.*Tag: *v//p')" == "$VERSION" ]]; then
    echo "talosctl $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://talos.dev/install -O "$tmpdir/install"
    export INSTALLPATH=$BIN_PATH TALOSCTL_VERSION=$VERSION && $MODIFIER bash "$tmpdir/install"
    rm -rf "$tmpdir"
  fi

  talosctl completion bash >completion_talosctl
  $USE_SUDO mv -f completion_talosctl $COMPLETION_FOLDER/talosctl
  add_to_profile talosctl "source $COMPLETION_FOLDER/talosctl
alias tctl=talosctl"
  talosctl version --client
}

function python_install() {
  log_red "Installing python"
  if [[ "$TERMUX" == "true" ]]; then
    apt install -y python
    pip install pipx
  else
    $USE_SUDO apt install -y python3 python3-pip python-is-python3 python3-setuptools pip pipx
  fi
  python --version
}

function speedtest_install() {
  log_red "Installing speedtest"

  add_to_profile speedtest 'alias speedtest="wget -O /dev/null https://proof.ovh.net/files/10Gb.dat"
alias fast=speedtest'
}

function operator_sdk_install() {
  log_red "Installing operator-sdk"

  VERSION=$($_CURL https://api.github.com/repos/operator-framework/operator-sdk/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name')
  if [[ "$(operator-sdk version 2>/dev/null | sed -E 's/.*version: "([^"]+)".*"v([^"]+)".*/\1/')" == "$VERSION" ]]; then
    echo "operator-sdk $VERSION already installed, skipping build"
  else
    if [[ "$TERMUX" == "true" ]]; then
      git clone https://github.com/operator-framework/operator-sdk.git
      pushd operator-sdk
      git checkout $VERSION
      make install
      popd
      rm -rf operator-sdk
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://github.com/operator-framework/operator-sdk/releases/latest/download/operator-sdk_linux_${PKG_ARCH} -O "$tmpdir/operator-sdk"
      chmod +x "$tmpdir/operator-sdk"
      $USE_SUDO mv -f "$tmpdir/operator-sdk" $BIN_PATH
      rm -rf "$tmpdir"
    fi
  fi

  operator-sdk completion bash >completion_operator_sdk
  $USE_SUDO mv -f completion_operator_sdk $COMPLETION_FOLDER/operator-sdk
  add_to_profile operator_sdk "source $COMPLETION_FOLDER/operator-sdk"
  operator-sdk version
}

function argocd_install() {
  log_red "Installing argocd"

  VERSION=$($_CURL https://api.github.com/repos/argoproj/argo-cd/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name')
  if [[ "$(argocd version --client --short 2>/dev/null | sed -E 's/.*(v[0-9.]*).*/\1/')" == "$VERSION" ]]; then
    echo "argocd $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-$PKG_ARCH -O "$tmpdir/argocd"
    chmod +x "$tmpdir/argocd"
    $USE_SUDO mv -f "$tmpdir/argocd" $BIN_PATH
    rm -rf "$tmpdir"
  fi

  argocd completion bash >completion_argocd
  $USE_SUDO mv -f completion_argocd $COMPLETION_FOLDER/argocd
  add_to_profile argocd "source $COMPLETION_FOLDER/argocd"
  argocd version --client
}

function virtctl_install() {
  log_red "Installing virtctl"

  VERSION=$($_CURL https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)

  if [[ "$TERMUX" == "true" ]]; then
    :
  else
    kubectl krew install virt
  fi

  if [[ "$(virtctl version --client 2>/dev/null | sed -n 's/.*GitVersion:"\([^"]*\)".*/\1/p')" == "$VERSION" ]]; then
    echo "virtctl $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-$PKG_ARCH -O "$tmpdir/virtctl"
    chmod +x "$tmpdir/virtctl"
    $USE_SUDO mv -f "$tmpdir/virtctl" $BIN_PATH
    rm -rf "$tmpdir"
  fi

  virtctl completion bash >completion_virtctl
  $USE_SUDO mv -f completion_virtctl $COMPLETION_FOLDER/virtctl
  add_to_profile virtctl "source $COMPLETION_FOLDER/virtctl
alias v=virtctl
alias vc=virtctl
complete -F __start_virtctl v
complete -F __start_virtctl vc"
  virtctl version --client
}

function neovim_install() {
  log_red "Installing neovim"

  export USE_SUDO_PROXY="$USE_SUDO"
  $USE_SUDO apt install -y npm

  if [[ "$TERMUX" == "true" ]]; then
    apt install -y ruby neovim lua54 luarocks lua-language-server rust
    cargo install stylua
    add_to_profile stylua 'export PATH=$PATH:$HOME/.cargo/bin'
    go install github.com/hashicorp/terraform-ls@latest
  else
    if [ -n "$http_proxy" ]; then
      echo using proxy for npm
      npm config set proxy $http_proxy
      npm config set https-proxy $http_proxy
      export USE_SUDO_PROXY="$USE_SUDO https_proxy=$https_proxy"
    fi

    $USE_SUDO npm install -g n
    $USE_SUDO_PROXY n lts
    $USE_SUDO_PROXY npm install -g tree-sitter-cli
    $USE_SUDO apt -y install ruby-full fd-find lua5.4 liblua5.4-0 liblua5.4-dev

    VERSION=$($_CURL https://api.github.com/repos/neovim/neovim/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
    if [[ "$(nvim --version 2>/dev/null | sed -n 's/^NVIM v//p')" == "$VERSION" ]]; then
      echo "neovim $VERSION already installed, skipping download"
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$OS_ARCH.appimage -O "$tmpdir/nvim"
      chmod u+x "$tmpdir/nvim"
      $USE_SUDO mv -f "$tmpdir/nvim" $BIN_PATH
      rm -rf "$tmpdir"
    fi

    tmpdir="$(mktemp -d)"
    $_WGET https://luarocks.org/releases/luarocks-3.13.0.tar.gz -O "$tmpdir/luarocks.tar.gz"
    pushd $tmpdir
    tar -xvf luarocks.tar.gz
    pushd luarocks-*
    $USE_SUDO_PROXY bash -c './configure && make && make install'
    $USE_SUDO_PROXY luarocks install luasocket
    popd
    popd
    $USE_SUDO rm -rf "$tmpdir"
  fi

  rm -rf $HOME/.config/nvim

  NEOVIM_SOURCE_GIT=${NEOVIM_SOURCE_GIT:-"https://github.com/lallinger/neovim.git"}
  git clone $NEOVIM_SOURCE_GIT $HOME/.config/nvim

  add_to_profile neovim "alias vim=nvim
  git config --global core.editor nvim
  export EDITOR=nvim
  export VISUAL=nvim"

  if [[ "${NEOVIM_NO_TOUCHY}" == "true" ]]; then
    return 0
  fi

  if [[ "$TERMUX" == "true" ]]; then
    echo 'return {
  {
    "mason-org/mason-lspconfig.nvim",
    opts = function(_, opts)
      -- Ensure ensure_installed exists
      opts.ensure_installed = opts.ensure_installed or {}

      -- Filter out lua_ls from mason-lspconfig specifically
      opts.ensure_installed = vim.tbl_filter(function(server)
        return server ~= "lua_ls"
      end, opts.ensure_installed)
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        terraformls = {
          mason = false,
          cmd = { vim.fn.expand("$HOME/go/bin/terraform-ls"), "serve" },
        },
        lua_ls = {
          mason = false,
          cmd = { "lua-language-server" },
        },
      },
    },
  },
}' >$HOME/.config/nvim/lua/plugins/lsp.lua

    echo 'return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Add both variations just to be safe
      local unsupported = { "stylua", "lua-language-server", "lua_ls", "terraformls" }
      opts.ensure_installed = opts.ensure_installed or {}

      local filtered = {}
      for _, pkg in ipairs(opts.ensure_installed) do
        local is_unsupported = false
        for _, unsupp_name in ipairs(unsupported) do
          if pkg == unsupp_name then
            is_unsupported = true
            break
          end
        end
        if not is_unsupported then
          table.insert(filtered, pkg)
        end
      end
      opts.ensure_installed = filtered
    end,
  },
}' >$HOME/.config/nvim/lua/plugins/mason.lua

    echo 'vim.opt.smoothscroll = false' >$HOME/.config/nvim/lua/config/options.lu
  fi

  $USE_SUDO_PROXY gem install neovim

  export OSC52_FIX='-- fix for terminal copy/paste timeout
function no_paste(reg)
    return function(lines)
        -- Do nothing! We cant paste with OSC52
    end
end

vim.g.clipboard = {
    name = "OSC 52",
    copy = {
         ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
         ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
        ["+"] = no_paste("+"), -- Pasting disabled
        ["*"] = no_paste("*"), -- Pasting disabled
    }
}'

  export OSC52_FIX_TERMUX='-- fix for windows terminal copy/paste timeout
function no_paste(reg)
    return function(lines)
        -- Do nothing! We cant paste with OSC52
    end
end

vim.g.clipboard = {
    name = "OSC 52",
    copy = {
         ["+"] = "termux-clipboard-set",
         ["*"] = "termux-clipboard-set",
    },
    paste = {
        ["+"] = "termux-clipboard-get",
         ["*"] = "termux-clipboard-get",
    }
}
vim.opt.clipboard = "unnamedplus"'

  termux-info && log_red "on termux" && echo "$OSC52_FIX_TERMUX" >>$HOME/.config/nvim/init.lua || (log_red "on normal linux" && echo "$OSC52_FIX" >>$HOME/.config/nvim/init.lua)

}

function chatgpt_install() {
  log_red "Installing chatgpt"

  VERSION=$($_CURL https://api.github.com/repos/kardolus/chatgpt-cli/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$(chatgpt --version 2>/dev/null | sed 's/.*v\([0-9.]*\).*/\1/')" == "$VERSION" ]]; then
    echo "chatgpt $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/kardolus/chatgpt-cli/releases/latest/download/chatgpt-linux-$PKG_ARCH -O "$tmpdir/chatgpt"
    chmod +x "$tmpdir/chatgpt"
    $USE_SUDO mv "$tmpdir/chatgpt" $BIN_PATH
    rm -rf "$tmpdir"
  fi
  mkdir -p $HOME/.chatgpt-cli

  chatgpt completion bash >completion_chatgpt
  $USE_SUDO mv -f completion_chatgpt $COMPLETION_FOLDER/chatgpt

  if [[ "$TERMUX" == "true" ]]; then
    add_to_profile chatgpt "source $COMPLETION_FOLDER/chatgpt
alias c=\"$PROOT_DNS_CERTS chatgpt\"
complete -C $BIN_PATH/chatgpt c
export OPENAI_MODEL=gpt-5-mini
export OPENAI_TRACK_TOKEN_USAGE=true
export OPENAI_ROLE='You are a seasoned tech veteran and cut right to the chase, no uneccessary output, minimalistic examples'
export OPENAI_API_KEY=\$(bws secret list | yq e '.[] | select(.key == \"openai-api-key\") | .value')"
  else
    add_to_profile chatgpt "source $COMPLETION_FOLDER/chatgpt
alias c=chatgpt
complete -C $BIN_PATH/chatgpt c
export OPENAI_MODEL=gpt-5-mini
export OPENAI_TRACK_TOKEN_USAGE=true
export OPENAI_ROLE='You are a seasoned tech veteran and cut right to the chase, no uneccessary output, minimalistic examples'
export OPENAI_API_KEY=\$(bws secret list | yq e '.[] | select(.key == \"openai-api-key\") | .value')"

  fi

  chatgpt --version
}

function gemini_install() {
  log_red "Installing gemini"

  if [[ "$TERMUX" == "true" ]]; then
    mkdir -p $HOME/.gyp && echo "{'variables':{'android_ndk_path':''}}" >$HOME/.gyp/include.gypi
  fi

  add_to_profile gemini 'alias g=gemini
  alias gi="gemini -i"'"
export GEMINI_API_KEY=\$(bws secret list | yq e '.[] | select(.key == \"gemini-api-key\") | .value')"

  $USE_SUDO npm install -g @google/gemini-cli

  mkdir -p $HOME/.gemini
  echo '{
  "general": {
    "vimMode": true,
    "preferredEditor": "vim",
    "previewFeatures": true,
    "sessionRetention": {
      "enabled": true,
      "maxAge": "30d"
    }
  },
  "privacy": {
    "usageStatisticsEnabled": false
  }
}' >$HOME/.gemini/settings.json
  gemini --version
}

function codex_install() {
  log_red "Installing codex"

  if [[ "$TERMUX" == "true" ]]; then
    apt install -y codex
  else
    $USE_SUDO npm i -g @openai/codex
  fi

  codex completion bash >completion_codex
  $USE_SUDO mv -f completion_codex $COMPLETION_FOLDER/codex
  add_to_profile codex "source $COMPLETION_FOLDER/codex
alias co=codex"
  codex --version
}

function vault_install() {
  log_red "Installing vault"

  VERSION=$($_CURL https://api.github.com/repos/hashicorp/vault/releases | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name' | sed 's/v//g')
  if [[ "$(vault version 2>/dev/null | sed 's/.*v\([0-9.]*\).*/\1/')" == "$VERSION" ]]; then
    echo "vault $VERSION already installed, skipping build"
  else
    if [[ "$TERMUX" == "true" ]]; then
      git clone https://github.com/hashicorp/vault.git
      pushd vault
      git checkout v$VERSION
      log_red "building vault may take quite some time depending on your device!"
      make bootstrap || echo "ignore make bootstrap error"
      make
      mv -f bin/vault $BIN_PATH
      popd
      rm -rf vault
    else
      tmpdir="$(mktemp -d)"
      $_WGET https://releases.hashicorp.com/vault/$VERSION/vault_${VERSION}_linux_${PKG_ARCH}.zip -O "$tmpdir/vault.zip"
      unzip "$tmpdir/vault.zip" -d "$tmpdir"
      $USE_SUDO mv -f "$tmpdir/vault" $BIN_PATH
      rm -rf "$tmpdir"
    fi
  fi

  vault -autocomplete-install || echo "vault autocomplete already installed"
  vault version
}

function bitwarden_install() {
  log_red "Installing bitwarden"

  VERSION=$($_CURL https://api.github.com/repos/bitwarden/sdk-sm/releases | jq -r '.[] | select(.tag_name | test("bws"; "i")) | .tag_name' | head -1 | sed 's/bws-v//g')

  if [[ "$TERMUX" == "true" ]]; then
    export BWS_ARCH=musl
  else
    export BWS_ARCH=gnu
  fi

  if [[ "$(bws --version 2>/dev/null | sed -n 's/^bws //p')" == "$VERSION" ]]; then
    echo "bitwarden (bws) $VERSION already installed, skipping download"
  else
    tmpdir="$(mktemp -d)"
    $_WGET https://github.com/bitwarden/sdk-sm/releases/download/bws-v$VERSION/bws-$OS_ARCH-unknown-linux-$BWS_ARCH-$VERSION.zip -O "$tmpdir/bws.zip"
    unzip "$tmpdir/bws.zip" -d "$tmpdir"
    $USE_SUDO mv -f "$tmpdir/bws" $BIN_PATH
    rm -rf "$tmpdir"
    if [[ "$TERMUX" == "true" ]]; then
      pushd $BIN_PATH
      mv -f bws _bws
      echo "#!$PREFIX/bin/bash
$PROOT_DNS_CERTS $BIN_PATH/_bws \$@" >bws
      chmod +x bws
      popd
    fi
  fi

  bws completions bash >completion_bitwarden
  $USE_SUDO mv -f completion_bitwarden $COMPLETION_FOLDER/bitwarden

  add_to_profile bitwarden "source $COMPLETION_FOLDER/bitwarden
source $HOME/.secure_vars"

  touch $HOME/.secure_vars
  chmod 600 $HOME/.secure_vars
  source $HOME/.secure_vars
  log_red "Set BWS_ACCESS_TOKEN in $HOME/secure_vars"
  bws --version
}

function linux_desktop_install() {
  echo
  if systemctl is-enabled display-manager >/dev/null 2>&1; then
    log_red "Display manager enabled (GUI expected)"
  else
    log_red "No enabled display manager"
    return 0
  fi

  $USE_SUDO apt install xfce4-settings thunar brave-browser terminator
  xdg-mime default thunar.desktop inode/directory application/x-gnome-saved-search
  echo '[Default Applications]
text/html=brave-browser.desktop
x-scheme-handler/http=xfce4-web-browser.desktop
x-scheme-handler/https=xfce4-web-browser.desktop
x-scheme-handler/about=brave-browser.desktop
x-scheme-handler/unknown=brave-browser.desktop
inode/directory=thunar.desktop
application/x-gnome-saved-search=thunar.desktop
application/x-csh=userapp-nvim-0XR7G3.desktop
application/x-shellscript=userapp-nvim-0XR7G3.desktop
text/tcl=userapp-nvim-0XR7G3.desktop
text/x-c++hdr=userapp-nvim-0XR7G3.desktop
text/x-c++src=userapp-nvim-0XR7G3.desktop
text/x-chdr=userapp-nvim-0XR7G3.desktop
text/x-csharp=userapp-nvim-0XR7G3.desktop
text/x-csrc=userapp-nvim-0XR7G3.desktop
text/x-dsrc=userapp-nvim-0XR7G3.desktop
text/x-gradle=userapp-nvim-0XR7G3.desktop
text/x-groovy=userapp-nvim-0XR7G3.desktop
text/x-java=userapp-nvim-0XR7G3.desktop
text/x-makefile=userapp-nvim-0XR7G3.desktop
text/x-moc=userapp-nvim-0XR7G3.desktop
text/x-mof=userapp-nvim-0XR7G3.desktop
text/x-objc++src=userapp-nvim-0XR7G3.desktop
text/x-objcsrc=userapp-nvim-0XR7G3.desktop
text/x-ooc=userapp-nvim-0XR7G3.desktop
text/x-opencl-src=userapp-nvim-0XR7G3.desktop
text/x-pascal=userapp-nvim-0XR7G3.desktop
text/x-tex=userapp-nvim-0XR7G3.desktop
text/x-vala=userapp-nvim-0XR7G3.desktop
application/geo+json=brave-browser.desktop
application/jrd+json=brave-browser.desktop
application/json=brave-browser.desktop
application/json-patch+json=brave-browser.desktop
application/ld+json=brave-browser.desktop
application/schema+json=brave-browser.desktop
audio/ogg=brave-browser.desktop
application/x-ipynb+json=brave-browser.desktop
application/x-gerber-job=brave-browser.desktop
application/x-xpinstall=brave-browser.desktop
audio/flac=brave-browser.desktop
audio/webm=brave-browser.desktop
audio/x-flac+ogg=brave-browser.desktop
audio/x-opus+ogg=brave-browser.desktop
audio/x-speex+ogg=brave-browser.desktop
audio/x-vorbis+ogg=brave-browser.desktop
image/avif=brave-browser.desktop
model/gltf+json=brave-browser.desktop
video/ogg=brave-browser.desktop
video/webm=brave-browser.desktop
video/x-ogm+ogg=brave-browser.desktop
video/x-theora+ogg=brave-browser.desktop
application/appx=thunar.desktop
application/appxbundle=thunar.desktop
application/java-archive=thunar.desktop
application/ovf=thunar.desktop
application/vnd.apple.numbers=thunar.desktop
application/vnd.apple.pages=thunar.desktop
application/vnd.apple.keynote=thunar.desktop
application/vnd.android.package-archive=thunar.desktop
application/vnd.apple.pkpass=thunar.desktop
application/vnd.google-earth.kmz=thunar.desktop
application/vnd.ms-officetheme=thunar.desktop
application/vnd.ms-visio.stencil.main+xml=thunar.desktop
application/vnd.ms-visio.template.main+xml=thunar.desktop
application/x-7z-compressed=thunar.desktop
application/x-bzip2=thunar.desktop
application/x-bzip2-compressed-tar=thunar.desktop
application/x-compress=thunar.desktop
application/x-compressed-tar=thunar.desktop
application/x-gz-font-linux-psf=thunar.desktop
application/x-lzip=thunar.desktop
application/x-lzip-compressed-tar=thunar.desktop
application/x-tar=thunar.desktop
application/x-tarz=thunar.desktop
application/x-xar=thunar.desktop
application/x-xz=thunar.desktop
application/x-xz-compressed-tar=thunar.desktop
application/x-zip-compressed-fb2=thunar.desktop
application/x-zstd-compressed-tar=thunar.desktop
application/zip=thunar.desktop
application/epub+zip=thunar.desktop
application/gzip=thunar.desktop
x-scheme-handler/http=xfce4-web-browser.desktop;
x-scheme-handler/https=xfce4-web-browser.desktop;
application/x-csh=userapp-nvim-0XR7G3.desktop;
application/x-shellscript=userapp-nvim-0XR7G3.desktop;
text/tcl=userapp-nvim-0XR7G3.desktop;
text/x-c++hdr=userapp-nvim-0XR7G3.desktop;
text/x-c++src=userapp-nvim-0XR7G3.desktop;
text/x-chdr=userapp-nvim-0XR7G3.desktop;
text/x-csharp=userapp-nvim-0XR7G3.desktop;
text/x-csrc=userapp-nvim-0XR7G3.desktop;
text/x-dsrc=org.gnome.TextEditor.desktop;userapp-nvim-0XR7G3.desktop;
text/x-gradle=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-groovy=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-java=userapp-nvim-0XR7G3.desktop;
text/x-makefile=userapp-nvim-0XR7G3.desktop;
text/x-moc=userapp-nvim-0XR7G3.desktop;
text/x-mof=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-objc++src=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-objcsrc=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-ooc=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-opencl-src=vim.desktop;userapp-nvim-0XR7G3.desktop;
text/x-pascal=userapp-nvim-0XR7G3.desktop;
text/x-tex=userapp-nvim-0XR7G3.desktop;
text/x-vala=vim.desktop;userapp-nvim-0XR7G3.desktop;
application/geo+json=brave-browser.desktop;
application/jrd+json=brave-browser.desktop;
application/json=brave-browser.desktop;
application/json-patch+json=org.gnome.TextEditor.desktop;brave-browser.desktop;
application/ld+json=firefox_firefox.desktop;brave-browser.desktop;
application/schema+json=firefox_firefox.desktop;brave-browser.desktop;
audio/ogg=brave-browser.desktop;
application/x-ipynb+json=firefox_firefox.desktop;brave-browser.desktop;
application/x-gerber-job=firefox_firefox.desktop;brave-browser.desktop;
application/x-xpinstall=brave-browser.desktop;
audio/flac=brave-browser.desktop;
audio/webm=brave-browser.desktop;
audio/x-flac+ogg=firefox_firefox.desktop;brave-browser.desktop;
audio/x-opus+ogg=firefox_firefox.desktop;brave-browser.desktop;
audio/x-speex+ogg=firefox_firefox.desktop;brave-browser.desktop;
audio/x-vorbis+ogg=firefox_firefox.desktop;brave-browser.desktop;
image/avif=brave-browser.desktop;
model/gltf+json=firefox_firefox.desktop;brave-browser.desktop;
video/ogg=brave-browser.desktop;
video/webm=brave-browser.desktop;
video/x-ogm+ogg=firefox_firefox.desktop;brave-browser.desktop;
video/x-theora+ogg=firefox_firefox.desktop;brave-browser.desktop;
application/appx=thunar.desktop;
application/appxbundle=thunar.desktop;
application/java-archive=thunar.desktop;
application/ovf=thunar.desktop;
application/vnd.apple.numbers=thunar.desktop;
application/vnd.apple.pages=thunar.desktop;
application/vnd.apple.keynote=thunar.desktop;
application/vnd.android.package-archive=org.gnome.Nautilus.desktop;thunar.desktop;
application/vnd.apple.pkpass=thunar.desktop;
application/vnd.google-earth.kmz=thunar.desktop;
application/vnd.ms-officetheme=thunar.desktop;
application/vnd.ms-visio.stencil.main+xml=thunar.desktop;
application/vnd.ms-visio.template.main+xml=thunar.desktop;
application/x-7z-compressed=thunar.desktop;
application/x-bzip2=thunar.desktop;
application/x-bzip2-compressed-tar=thunar.desktop;
application/x-compress=thunar.desktop;
application/x-compressed-tar=thunar.desktop;
application/x-gz-font-linux-psf=thunar.desktop;
application/x-lzip=thunar.desktop;
application/x-lzip-compressed-tar=thunar.desktop;
application/x-tar=thunar.desktop;
application/x-tarz=thunar.desktop;
application/x-xar=thunar.desktop;
application/x-xz=thunar.desktop;
application/x-xz-compressed-tar=thunar.desktop;
application/x-zip-compressed-fb2=thunar.desktop;
application/x-zstd-compressed-tar=thunar.desktop;
application/zip=thunar.desktop;
application/epub+zip=org.gnome.Nautilus.desktop;thunar.desktop;
application/gzip=thunar.desktop;' >$HOME/.config/mimeapps.list

  echo '[global_config]
[keybindings]
  split_auto = <Primary>t
  close_term = <Primary>w
  copy = <Primary>c
  paste = <Primary>v
[profiles]
  [[default]]
    font = JetBrainsMono Nerd Font 12
    foreground_color = "#ffffff"
    scrollback_infinite = True
    palette = "#000000:#aa0000:#00aa00:#aa5500:#0000aa:#aa00aa:#00aaaa:#aaaaaa:#555555:#ff5555:#55ff55:#ffff55:#5555ff:#ff55ff:#55ffff:#ffffff"
    use_system_font = False
[layouts]
  [[default]]
    [[[window0]]]
      type = Window
      parent = ""
    [[[child1]]]
      type = Terminal
      parent = window0
      profile = default
[plugins]' >$HOME/.config/terminator/config

  sed -i 's/vim\.g\.clipboard = "osc52" --for ssh/vim\.api\.nvim_set_option\("clipboard", "unnamed"\) --for desktop linux/g' $HOME/.config/nvim/init.lua
}

function miscelanious_install() {
  log_red "Installing miscelanious"
  $USE_SUDO apt install -y duf gdu dos2unix rclone zoxide htop net-tools tree lsd tmux unzip

  FONT_FOLDER=$HOME/.local/share/fonts
  FONT_NAME="JetBrainsMonoNerdFont-Regular.ttf"
  export INPUTRC_LOCATION=/etc/inputrc
  if [[ "$TERMUX" == "true" ]]; then
    export INPUTRC_LOCATION=$PREFIX/etc/inputrc
    apt install -y which ncurses-utils apache2 # apache2 => needed for htpasswd for argocd bcrypt
    FONT_FOLDER=$HOME/.termux
    FONT_NAME=font.ttf
  else
    $USE_SUDO apt install -y iotop dropbear bind9-dnsutils net-tools sqlite3 apache2-utils # apache2-utils => needed for htpasswd for argocd bcrypt
  fi

  mkdir -p $FONT_FOLDER
  cat $FONT_FOLDER/$FONT_NAME >/dev/null || ($_WGET https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && unzip JetBrainsMono.zip -d fonts && mv -f fonts/JetBrainsMonoNerdFont-Regular.ttf $FONT_FOLDER/$FONT_NAME && rm -rf fonts JetBrainsMono.zip)

  $USE_SUDO bash -c "echo 'set completion-ignore-case On' >> $INPUTRC_LOCATION"

  zoxide init bash >completion_zoxide
  $USE_SUDO mv -f completion_zoxide $COMPLETION_FOLDER/zoxide

  add_to_profile zoxide "source $COMPLETION_FOLDER/zoxide
alias cd=z"

  add_to_profile gdu 'alias du=gdu'

  add_to_profile icanhazip 'alias icanhazip="curl icanhazip.com"'

  add_to_profile duf 'alias df=duf'

  add_to_profile lsd 'alias ls=lsd
alias ll="lsd -l"'

  add_to_profile grep "alias grepf='grep -HIirn --color=always'"

  add_to_profile git 'git config --global core.autocrlf false
git config --global core.eol lf
git config --global core.filemode false
# always use ssh
# git config --global url.ssh://git@github.com/.insteadOf https://github.com/
alias gitwip="git add . && git commit -m wip && git pull --rebase && git push"
alias gitgud='"'"'_gitgud() { args="$@" && git add . && git commit -m "$args" && git pull --rebase && git push ;}; _gitgud'"'
alias gg=gitgud
alias gwip=gitwip
alias gc='git clone'
alias gs='git status'"

  add_to_profile prompt 'WHITE=$(tput setaf 7)
CYAN=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
BLUE=$(tput setaf 6)
GREEN=$(tput setaf 34)

GET_CTX="\$(kubectl config current-context 2> /dev/null)"
GET_NS="\$(kubectl config view --minify -o jsonpath='"'{..namespace}'"' 2> /dev/null)"

export PS1="\[$WHITE\][\[$CYAN\]\T\[$WHITE\]]\[$WHITE\][\[$MAGENTA\]\u@\h\[$WHITE\]]\[$WHITE\][\[$MAGENTA\]${GET_CTX}/${GET_NS}\[$WHITE\]]\[$BLUE\]\w\[$WHITE\]:\[$GREEN\] "'

  sed -i 's/HISTSIZE.*//g' $_bashrc
  sed -i 's/HISTFILESIZE.*//g' $_bashrc

  add_to_profile hist '# Eternal bash history.
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE=$HOME/.eternal_history_bash
# Force prompt to write history after every command.
## http://superuser.com/questions/20900/bash-history-loss
alias hist="history -a && history -r"
#PROMPT_COMMAND="history -a; $PROMPT_COMMAND"'

  add_to_profile bashrc "alias bashrc=\"vim $_bashrc\"
alias src=\"source $_bashrc\""

  add_to_profile apt "USE_SUDO=$USE_SUDO"'
alias ai="$USE_SUDO apt install"
alias aiy="$USE_SUDO apt install -y"
alias alu="$USE_SUDO apt list --upgradable"
alias aupd="$USE_SUDO apt update"
alias aupg="$USE_SUDO apt upgrade"
alias ar="$USE_SUDO apt remove"'

  echo '#!/usr/bin/bash
cd /mnt/c/Users/$WIN_USER' >$HOME/.win_home
  add_to_profile home "alias home='source $HOME/.win_home'"

  echo 'bind -n M-Left previous-window
  bind -n M-Right next-window
  bind -n M-T new-window -c "#{pane_current_path}"
  bind -n M-Tab next-window
  bind -n M-Btab previous-window' >$HOME/.tmux.conf
}

function termux_install() {
  log_red "Installing termux specifics"

  pushd $HOME/.termux

  echo "cd $PREFIX" >$HOME/.prefix
  add_to_profile termux 'alias prefix="source $HOME/.prefix"
export PROOT_DNS_CERTS="proot -b $PREFIX/etc/resolv.conf:/etc/resolv.conf -b $PREFIX/etc/tls/cert.pem:/etc/ssl/certs/ca-certificates.crt"'
  export PROOT_DNS_CERTS="proot -b $PREFIX/etc/resolv.conf:/etc/resolv.conf -b $PREFIX/etc/tls/cert.pem:/etc/ssl/certs/ca-certificates.crt"

  export BIN_PATH=$PREFIX/bin
  mkdir -p $BIN_PATH
  add_to_profile path 'export PATH=$PATH:'"$BIN_PATH"
  export PATH=$PATH:$BIN_PATH

  cat termux.properties | grep terminal-transcript-rows || echo "terminal-transcript-rows = 100000" >>termux.properties

  apt install -y mandoc perl termux-auth openssh resolv-conf ca-certificates proot x11-repo tur-repo termux-api
  cat $HOME/.termux_authinfo >/dev/null || passwd

  echo 'background:     #000000
foreground:     #00FF00
cursor:     #00FF00
color0:         #000000
color1:         #990000
color2:         #00A600
color3:         #999900
color4:         #0000B2
color5:         #B200B2
color6:         #00A6B2
color7:         #BFBFBF
color8:         #666666
color9:         #E50000
color10:         #00D900
color11:         #E5E500
color12:         #0000FF
color13:         #E500E5
color14:         #00E5E5
color15:         #E5E5E5' >colors.properties

  ls $HOME/downloads >/dev/null || (termux-setup-storage && ln -s $HOME/storage/downloads $HOME/downloads)

  mkdir -p boot
  echo '#!$PREFIX/bin/sh
termux-wake-lock
sshd' >boot/start.sh
  chmod +x boot/start.sh

  popd
}

function finish() {
  custom_install || echo "no customization active"       # function found in $HOME/.workbench
  add_to_profile kubectl "source $HOME/.kubectl_aliases" # somehow completion only works when it's sourced last. kubectl section gets added in miscelanious_install
}

install_tools() {
  prepare
  miscelanious_install
  go_install
  neovim_install
  linux_desktop_install
  bitwarden_install
  terraform_install
  yq_install
  kustomize_install
  helm_install
  kubectl_install
  oc_install
  krew_install
  kubectx_install
  netshoot_install
  k9s_install
  kubecolor_install
  docker_install
  kubectl_neat_install
  istioctl_install
  kyverno_install
  mc_install
  ccat_install
  talosctl_install
  python_install
  speedtest_install
  operator_sdk_install
  argocd_install
  virtctl_install
  chatgpt_install
  gemini_install
  codex_install
  vault_install
  finish
}

install_tools

log_red "setup.sh finished successfully! Run 'source $HOME/.bashrc' or open a new bash shell to start using!"
