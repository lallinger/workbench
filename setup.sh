#!/usr/bin/env bash

set -e

export COMPLETION_FOLDER="/usr/share/bash-completion/completions"
mkdir -p $COMPLETION_FOLDER
_bashrc=$HOME/.bashrc

add_to_profile() {
  section=$1
  code=$2

  grep "#$section" $_bashrc && (echo "found section $section, replacing" && sed -i "/#$section/,/#\/$section/d" $_bashrc && sed -i '/^$/N;/\n$/s/\n//;P;D' $_bashrc) || echo -n
  
  echo "" >> $_bashrc
  echo "#$section" >> $_bashrc
  echo "$code" >> $_bashrc
  echo "#/$section" >> $_bashrc
  source $_bashrc
}

function prepare() {
  rm /etc/apt/apt.conf.d/docker-clean || echo "docker-clean not found => skipping delete" # enable shell completion for apt in ubuntu docker image
  add_to_profile xdg 'XDG_CONFIG_HOME="$HOME/.config"'
  apt update
  export TZ=Europe/Berlin
  echo $TZ > /etc/timezone
  export DEBIAN_FRONTEND=noninteractive
  apt install -y curl wget git tzdata vim bash-completion apt-utils jq
  apt upgrade -y
  add_to_profile bash_completion 'source /etc/bash_completion'
}


function terraform_install() {
  echo "\e[31minstalling terraform\e[0m"
  apt install -y gnupg software-properties-common
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  wget -O- https://apt.releases.hashicorp.com/gpg |  gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  apt update
  apt install -y terraform
  terraform -install-autocomplete
  add_to_profile terraform 'complete -C /usr/bin/terraform tf
complete -C /usr/bin/terraform terraform
alias tf=terraform
alias tfi="terraform init"
alias tfp="terraform plan"
alias tfa="terraform apply"
alias tfaa="terraform apply -auto-approve"
alias tfd="terraform destroy"
alias tfda="terraform destroy -auto-approve"'
  terraform --version
}

function az_install() {
  echo "\e[31minstalling az\e[0m"
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  az --version
}

function kustomize_install() {
  echo "\e[31minstalling kustomize\e[0m"
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -
  mv kustomize /usr/bin/
  kustomize completion bash > completion_kustomize
  mv completion_kustomize $COMPLETION_FOLDER/kustomize
  add_to_profile kustomize "source $COMPLETION_FOLDER/kustomize"
  kustomize version
}

function helm_install() {
  echo "\e[31minstalling helm\e[0m"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm completion bash > completion_helm
  mv completion_helm $COMPLETION_FOLDER/helm
  add_to_profile helm "source $COMPLETION_FOLDER/helm"
  helm version
}

function kubectl_install() {
  echo "\e[31minstalling kubectl\e[0m"
  curl -LO https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
  chmod +x kubectl
  mv kubectl /usr/bin
  kubectl completion bash > completion_kubectl

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
    elif [[ "${words[0]}" == "kng" ]] ; then\
        __kubectl_debug  "called kng"\
        words=("kubectl" "neat" "get" "${words[@]:1}")\
        cword=$(($cword+2))\
        prev="get"\
    else \
        __kubectl_debug "${words[0]} is not a known alias => not manipulating"\
        unmanipulated=un\
    fi\
    __kubectl_debug "${unmanipulated}manipulated prev '"'"'${prev}'"'"' words '"'"'${words[*]}'"'"', cword '"'"'$cword'"'"'"\
'

  grep "#$section" completion_kubectl && (echo "found section $section, replacing" && sed -i "/#$section/,/#\/$section/d" completion_kubectl && sed -i '/^$/N;/\n$/s/\n//;P;D' completion_kubectl) || echo -n

  sed -i '/__kubectl_debug "========= starting completion logic =========="/a'"\
#$section\
$code\
#\/$section" completion_kubectl

  sed -i 's/__kubectl_debug "========= starting completion logic =========="//g' completion_kubectl
  sed -i "/#\/$section/a"'\
    __kubectl_debug "========= starting completion logic =========="' completion_kubectl
  mv completion_kubectl $COMPLETION_FOLDER/kubectl

  echo "source $COMPLETION_FOLDER/kubectl"'
alias k=kubectl
alias kake="kustomize build --enable-helm . | kubectl apply -f -"
complete -F __start_kubectl k
complete -F __start_kubectl ka
alias k="kubectl apply"
complete -F __start_kubectl kak
alias k="kubectl apply -k"
complete -F __start_kubectl kaf
alias k="kubectl apply -f"
complete -F __start_kubectl krm
alias k="kubectl delete"
complete -F __start_kubectl krma
alias k="kubectl delete --all"
complete -F __start_kubectl kg
alias k="kubectl get"
complete -F __start_kubectl krmk
alias k="kubectl delete -k"
complete -F __start_kubectl krmf
alias k="kubectl delete -f"
complete -F __start_kubectl kcns
alias k="kubectl create ns"
complete -F __start_kubectl kng
alias k="kubectl neat get"
' > .kubectl_aliases # somehow completion only works when it's sourced last. kubectl section gets added in miscelanious_install

  kubectl version --client
}

function krew_install() {
  echo "\e[31minstalling krew\e[0m"
  (
    set -x; cd "$(mktemp -d)" &&
    OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
    KREW="krew-${OS}_${ARCH}" &&
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
    tar zxvf "${KREW}.tar.gz" &&
    ./"${KREW}" install krew
  )
  add_to_profile krew 'export PATH="$PATH:${KREW_ROOT:-$HOME/.krew}/bin"'
  # completion not yet working: https://github.com/kubernetes-sigs/krew/issues/812
  export PATH="$PATH:${KREW_ROOT:-$HOME/.krew}/bin" 
  kubectl krew version
}

function kubens_install() {
  echo "\e[31minstalling kubens\e[0m"
  $(find -iname krew -type f) install ns
  add_to_profile kubens 'alias kns="kubectl ns"'
  kubectl plugin list | grep kubectl-ns
}

function kubectx_install() {
  echo "\e[31minstalling kubectx\e[0m"
  $(find -iname krew -type f) install ctx
  add_to_profile kubectx 'alias kctx="kubectl ctx"'
  kubectl plugin list | grep kubectl-ctx
}

function netshoot_install() {
  echo "\e[31minstalling netshoot\e[0m"
  $(find -iname krew -type f) index add netshoot https://github.com/nilic/kubectl-netshoot.git
  $(find -iname krew -type f) install netshoot/netshoot
  add_to_profile netshoot 'alias netshoot="k netshoot run tmp"'
  kubectl plugin list | grep kubectl-netshoot
}

function k9s_install() {
  echo "\e[31minstalling k9s\e[0m"
  wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
  apt install -y --fix-missing ./k9s_linux_amd64.deb
  rm ./k9s_linux_amd64.deb
  k9s completion bash > completion_k9s
  mv completion_k9s $COMPLETION_FOLDER/k9s
  add_to_profile k9s "source $COMPLETION_FOLDER/k9s"
  k9s --version
}

function go_install() {
  echo "\e[31minstalling go\e[0m"

  if command -v go &>/dev/null; then
    echo "Found pre-existing Go version. removing..."
    rm -rf /usr/local/go
  fi

  GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | cut -d' ' -f3 | tr -d 'go')
  wget https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz -O go.tar.gz
  rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz
  add_to_profile go 'export PATH="$PATH:/usr/local/go/bin:'$HOME'/go/bin"'
  rm go.tar.gz
  export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
  go version
}

function kubecolor_install() {
  echo "\e[31minstalling kubecolor\e[0m"
  go install github.com/kubecolor/kubecolor@latest
  add_to_profile kubecolor "alias kc=kubecolor
  alias kubectl=kubecolor
complete -F __start_kubectl kubecolor"
  /root/go/bin/kubecolor
}

function podman_install() {
  echo "\e[31minstalling podman\e[0m"
  apt -y install podman
  add_to_profile podman 'alias docker=podman
function run-it() {
  docker run -v "${PWD}:/pwd" "$1" /bin/bash -c : || ( echo fallback to sh && docker run -it -v "${PWD}:/pwd" "$1" /bin/sh ) && docker run -it -v "${PWD}:/pwd" "$1" /bin/bash
}
export -f run-it
alias rit=run-it
alias dbt="docker build . -t"'

  podman --version
}

function kubectl_neat_install() {
  echo "\e[31minstalling kubectl neat\e[0m"
  $(find -iname krew -type f) install neat
  add_to_profile kubectl_neat 'alias kng="kubectl neat get"'
  kubectl plugin list | grep kubectl-neat
}

function yq_install(){
  echo "\e[31minstalling yq\e[0m"
  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
  chmod +x /usr/bin/yq
  yq completion bash > completion_yq
  mv completion_yq $COMPLETION_FOLDER/yq
  add_to_profile yq "source $COMPLETION_FOLDER/yq"
  yq --version
}

function ccat_install() {
  echo "\e[31minstalling ccat\e[0m"
  vversion=curl https://api.github.com/repos/batmac/ccat/releases | jq '.[0].tag_name' | sed 's/"//g'
  version=$(echo $vversion | sed 's/v//g')
  wget https://github.com/batmac/ccat/releases/download/$vversion/ccat-$version-linux-amd64.tar.gz -O ccat.tar.gz
  tar -xvf ccat.tar.gz
  mv ccat /usr/bin
  ccat --selfupdate
  rm ccat.tar.gz
  ccat -C bash > completion_ccat
  mv completion_ccat $COMPLETION_FOLDER/ccat
  add_to_profile ccat "alias cat=ccat
source $COMPLETION_FOLDER/ccat
complete -F _ccat_completions cat
alias _cat=/usr/bin/cat"

  ccat --version
}

function talosctl_install() {
  echo "\e[31minstalling talosctl\e[0m"
  curl -sL https://talos.dev/install | sh
  talosctl completion bash > completion_talosctl
  mv completion_talosctl $COMPLETION_FOLDER/talosctl
  add_to_profile talosctl "source $COMPLETION_FOLDER/talosctl
alias tctl=talosctl"
  talosctl version --client
}

function python_install() {
  echo "\e[31minstalling python\e[0m"
  apt install -y python3 python3-pip python-is-python3 python3-setuptools pip pipx
  python --version
}

function fuck_install() {
  echo "\e[31minstalling fuck\e[0m"
  pip install thefuck --break-system-packages
  # broken package for python 3.12... https://github.com/nvbn/thefuck/issues/1491
  python_version=$(python --version | sed 's/Python //g' | sed 's/\.[0-9]\+$//')
  rm /usr/local/lib/python$python_version/dist-packages/thefuck/conf.py
  rm /usr/local/lib/python$python_version/dist-packages/thefuck/types.py
  wget https://raw.githubusercontent.com/DL909/thefuck/refs/heads/imp-bug-fix/thefuck/types.py -O /usr/local/lib/python$python_version/dist-packages/thefuck/types.py
  wget https://raw.githubusercontent.com/nvbn/thefuck/f3af4c30da9bc8d2d168114f4d602fa03581eb62/thefuck/conf.py -O /usr/local/lib/python$python_version/dist-packages/thefuck/conf.py
  add_to_profile fuck 'alias f=fuck
eval $(thefuck --alias fuck)
export PATH=$PATH:/root/.local/bin'

  eval $(thefuck --alias fuck)
  fuck --version
}

function xxh_install() {
  echo "\e[31minstalling xxh\e[0m"
  apt install -y sshpass
  pipx install xxh-xxh
  add_to_profile xxh 'alias ssh=xxh
alias _ssh=/usr/bin/ssh'

  #ls $HOME/bin/xxh
}

function speedtest_install() {
  echo "\e[31minstalling speedtest\e[0m"
  add_to_profile speedtest 'alias speedtest="wget -O /dev/null https://proof.ovh.net/files/10Gb.dat"
alias fast=speedtest'
}

function miscelanious_install() {
  echo "installing miscelanious\e[0m"
  apt install -y htop iotop net-tools tree
  
  echo 'set completion-ignore-case On' >> /etc/inputrc

  add_to_profile git 'git config --global core.autocrlf false
git config --global core.eol lf
git config --global core.filemode false
alias gitwip="git add . && git commit -m wip && git pull --rebase && git push"
alias gitgud='"'"'_gitgud() { args="$@" && git add . && git commit -m "$args" && git pull --rebase && git push ;}; _gitgud'"'"

  add_to_profile prompt 'WHITE="\[$(tput setaf 7)\]"
CYAN="\[$(tput setaf 3)\]"
MAGENTA="\[$(tput setaf 5)\]"
BLUE="\[$(tput setaf 6)\]"
GREEN="\[$(tput setaf 34)\]"
TIME=$CYAN'"'\T'"'
USER_HOST=$MAGENTA'"'\u@\h'"'
KUBECTL=$MAGENTA'"'$(kubectl config current-context)'"'
CURRENT_PATH=$BLUE'"'\w'"'

export PS1="$WHITE[$TIME$WHITE]$WHITE[$USER_HOST$WHITE]$WHITE[$MAGENTA$WHITE]$CURRENT_PATH$WHITE: $GREEN"'

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
export HISTFILE=~/.eternal_history_bash
# Force prompt to write history after every command.
## http://superuser.com/questions/20900/bash-history-loss
alias hist="history -a"
#PROMPT_COMMAND="history -a; $PROMPT_COMMAND"'

  add_to_profile rename 'function rename() {
  path=$(echo -n $1 | sed "s|/[^/]*$|/|")
  mv $1 "$path"$2 
}'
  
  add_to_profile bashrc 'alias bashrc="vim ~/.bashrc"
alias src="source ~/.bashrc"'

  add_to_profile apt 'alias ai="apt install"
alias aiy="apt install -y"
alias alu="apt list --upgradable"
alias aupd="apt update"
alias aupg="apt upgrade"'

  add_to_profile kubectl "source ~/.kubectl_aliases"

  echo "set nocompatible
set nomodeline
syntax on
set ruler
set visualbell
set shiftwidth=2
set softtabstop=2
set number
set laststatus=2
set expandtab
set tabstop:2
set ignorecase
set smartcase
set backspace=indent,eol,start
set autoindent
set listchars=tab:▸\ 
set list
set confirm
set paste
if has('mouse')
  set mouse=a
endif
if has('filetype')
  filetype indent plugin on
endif
if has('syntax')
  syntax on
endif

" > $HOME/.vimrc
}

install_tools() {
  prepare
  terraform_install
  #az_install
  kustomize_install
  helm_install
  kubectl_install
  krew_install
  kubens_install
  kubectx_install
  netshoot_install
  k9s_install
  go_install
  kubecolor_install
  podman_install
  kubectl_neat_install
  yq_install
  ccat_install
  talosctl_install
  python_install
  fuck_install
  xxh_install
  speedtest_install
  miscelanious_install
}

install_tools
