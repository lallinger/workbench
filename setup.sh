#!/usr/bin/env bash
export COMPLETION_FOLDER="/usr/local/share/completions"
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

prepare() {
  rm /etc/apt/apt.conf.d/docker-clean # enable shell completion for apt in ubuntu docker image
  add_to_profile xdg 'XDG_CONFIG_HOME="$HOME/.config"'
  apt update
  export TZ=Europe/Berlin
  echo $TZ > /etc/timezone
  export DEBIAN_FRONTEND=noninteractive
  apt install -y curl wget git tzdata vim bash-completion
  apt upgrade -y
  add_to_profile bash_completion 'source /etc/bash_completion'
}


terraform_install () {
  echo "installing terraform"
  apt install -y gnupg software-properties-common
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  apt update && apt install -y terraform
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
}

az_install () {
  echo "installing az"
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash
}

kustomize_install () {
  echo "installing kustomize"
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -
  mv kustomize /usr/bin/
  kustomize completion bash > completion_kustomize
  mv completion_kustomize $COMPLETION_FOLDER/kustomize
  add_to_profile kustomize "source $COMPLETION_FOLDER/kustomize"
}

helm_install () {
  echo "installing helm"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm completion bash > completion_helm
  mv completion_helm $COMPLETION_FOLDER/helm
  add_to_profile helm "source $COMPLETION_FOLDER/helm"
}

kubecolor_install () {
  echo "installing kubecolor"
  apt install -y kubecolor 
  add_to_profile kubecolor "alias kubectl=kubecolor"
}

kubectl_install () {
  echo "installing kubectl"
  curl -LO https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
  chmod +x kubectl
  mv kubectl /usr/bin
  kubectl completion bash > completion_kubectl
  mv completion_kubectl $COMPLETION_FOLDER/kubectl

  add_to_profile kubectl "source $COMPLETION_FOLDER/kubectl
alias k=kubectl
complete -F __start_kubectl k
complete -f __start_kubectl kubecolor
alias ka='kubectl apply'
alias kaf='kubectl apply -f'
alias kak='kubectl apply -k'
alias krm='kubectl delete'
alias krma='kubectl delete --all'
alias kg='kubectl get'
alias kake='kustomize build --enable-helm . | kubectl apply -f -'
alias krmk='kubectl delete -k'
alias krmf='kubectl delete -f'
alias kcns='kubectl create ns'
alias kng='kubectl neat get'"
}

krew_install () {
  echo "installing krew"
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
}

kubens_install () {
  echo "installing kubens"
  $(find -iname krew -type f) install ns
  add_to_profile kubens 'alias kns="kubectl ns"'
}

kubectx_install () {
  echo "installing kubectx"
  $(find -iname krew -type f) install ctx
  add_to_profile kubectx 'alias kctx="kubectl ctx"'
}

netshoot_install () {
  echo "installing netshoot"
  $(find -iname krew -type f) index add netshoot https://github.com/nilic/kubectl-netshoot.git
  $(find -iname krew -type f) install netshoot/netshoot
  add_to_profile netshoot 'alias netshoot="k netshoot run tmp"'
}

k9s_install () {
  echo "installing k9s"
  wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
  apt install -y --fix-missing ./k9s_linux_amd64.deb
  rm ./k9s_linux_amd64.deb
  k9s completion bash > completion_k9s
  mv completion_k9s $COMPLETION_FOLDER/k9s
  add_to_profile k9s "source $COMPLETION_FOLDER/k9s"
}

go_install () {
  echo "installing go"
  GO_VERSION=1.23.5
  wget https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz -O go.tar.gz
  rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz
  add_to_profile go 'export PATH="$PATH:/usr/local/go/bin:/home/patrick/go/bin"'
  rm go.tar.gz
}

podman_install () {
  echo "installing podman"
  apt -y install podman
  add_to_profile podman 'alias docker=podman
function run-it() {
  docker run -v "${PWD}:/pwd" "$1" /bin/bash -c : || ( echo fallback to sh && docker run -it -v "${PWD}:/pwd" "$1" /bin/sh ) && docker run -it -v "${PWD}:/pwd" "$1" /bin/bash
}
export -f run-it
alias rit=run-it
alias dbt="docker build . -t"'
}

kubectl_neat_install () {
  echo "installing kubectl neat"
  $(find -iname krew -type f) install neat
  add_to_profile kubectl_neat 'alias kng="kubectl neat get"'
}

yq_install (){
  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
  chmod +x /usr/bin/yq
  yq completion bash > completion_yq
  mv completion_yq $COMPLETION_FOLDER/yq
  add_to_profile yq "source $COMPLETION_FOLDER/yq"
}

ccat_install() {
  version=1.17.2
  wget https://github.com/batmac/ccat/releases/download/v$version/ccat-$version-linux-amd64.tar.gz -O ccat.tar.gz
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
}

talosctl_install() {
  curl -sL https://talos.dev/install | sh
  talosctl completion bash > completion_talosctl
  mv completion_talosctl $COMPLETION_FOLDER/talosctl
  add_to_profile talosctl "source $COMPLETION_FOLDER/talosctl" 
}

python_install() {
  apt install -y python3 python3-pip python-is-python3 python3-setuptools pip pipx
}

fuck_install() {
  pip install thefuck --break-system-packages
  # broken package for python 3.12... https://github.com/nvbn/thefuck/issues/1491
  rm /usr/local/lib/python3.12/dist-packages/thefuck/conf.py
  rm /usr/local/lib/python3.12/dist-packages/thefuck/types.py
  wget https://raw.githubusercontent.com/DL909/thefuck/refs/heads/imp-bug-fix/thefuck/types.py -O /usr/local/lib/python3.12/dist-packages/thefuck/types.py
  wget https://raw.githubusercontent.com/nvbn/thefuck/f3af4c30da9bc8d2d168114f4d602fa03581eb62/thefuck/conf.py -O /usr/local/lib/python3.12/dist-packages/thefuck/conf.py
  add_to_profile fuck 'alias f=fuck
eval $(thefuck --alias fuck)
export PATH=$PATH:/root/.local/bin'
}

xxh_install() {
  apt install -y sshpass
  pipx install xxh-xxh
  add_to_profile xxh 'alias ssh=xxh
alias _ssh=/usr/bin/ssh'
}

miscelanious_install() {
  apt install -y htop vim iotop net-tools
  
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
  add_to_profile hist 'alias src="source ~/.bashrc"
# Eternal bash history.
# ---------------------
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE=~/.bash_eternal_history
# Force prompt to write history after every command.
# http://superuser.com/questions/20900/bash-history-loss
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"'
}

install_tools () {
  prepare
  terraform_install
  #az_install
  kustomize_install
  helm_install
  kubectl_install
  krew_install
  kubens_install
  kubectx_install
  #kubecolor_install # unfortunately breaks tab completion (12.2.25)
  netshoot_install
  k9s_install
  go_install
  podman_install
  kubectl_neat_install
  yq_install
  ccat_install
  talosctl_install
  python_install
  fuck_install
  xxh_install
  miscelanious_install
}

install_tools
