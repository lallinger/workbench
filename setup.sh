#!/usr/bin/env bash

set -e

export COMPLETION_FOLDER="/usr/share/bash-completion/completions"
mkdir -p $COMPLETION_FOLDER
_bashrc=$HOME/.bashrc

add_to_profile() {
  section=$1
  code=$2

  grep "#$section" $_bashrc && (echo "found section $section, replacing" && sed -i "/#$section/,/#\/$section/d" $_bashrc && sed -i '/^$/N;/\n$/s/\n//;P;D' $_bashrc) || echo -n

  echo "" >>$_bashrc
  echo "#$section" >>$_bashrc
  echo "$code" >>$_bashrc
  echo "#/$section" >>$_bashrc
  source $_bashrc
}

function prepare() {
  rm /etc/apt/apt.conf.d/docker-clean || echo "docker-clean not found => skipping delete" # enable shell completion for apt in ubuntu docker image
  add_to_profile xdg 'XDG_CONFIG_HOME="$HOME/.config"'
  apt update
  export TZ=Europe/Berlin
  echo $TZ >/etc/timezone
  export DEBIAN_FRONTEND=noninteractive
  apt install -y curl wget git tzdata bash-completion apt-utils jq
  apt upgrade -y
  add_to_profile bash_completion 'source /etc/bash_completion'
}

function terraform_install() {
  echo "\e[31minstalling terraform\e[0m"
  apt install -y gnupg software-properties-common
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  apt update
  apt install -y terraform
  #terraform -install-autocomplete
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
  mv -f kustomize /usr/local/bin/
  kustomize completion bash >completion_kustomize
  mv -f completion_kustomize $COMPLETION_FOLDER/kustomize
  add_to_profile kustomize 'source'" $COMPLETION_FOLDER/kustomize"'
alias touchk="touch kustomization.yaml && kustomize edit add resource *"'
  kustomize version
}

function helm_install() {
  echo "\e[31minstalling helm\e[0m"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm completion bash >completion_helm
  mv -f completion_helm $COMPLETION_FOLDER/helm
  add_to_profile helm "source $COMPLETION_FOLDER/helm"
  helm version
}

function kubectl_install() {
  echo "\e[31minstalling kubectl\e[0m"
  curl -LO https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
  chmod +x kubectl
  mv -f kubectl /usr/local/bin
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
#$section$code#\/$section" completion_kubectl
  sed -i 's/__kubectl_debug "========= starting completion logic =========="//g' completion_kubectl
  sed -i "/#\/$section/a"'\
    __kubectl_debug "========= starting completion logic =========="' completion_kubectl
  mv -f completion_kubectl $COMPLETION_FOLDER/kubectl

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
' >$HOME/.kubectl_aliases # somehow completion only works when it's sourced last. kubectl section gets added in miscelanious_install

  kubectl version --client
}

function krew_install() {
  echo "\e[31minstalling krew\e[0m"
  (
    set -x
    cd "$(mktemp -d)" &&
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
  $(find $HOME -iname krew -type f) install ns
  add_to_profile kubens 'alias kns="kubectl ns"'
  kubectl plugin list | grep kubectl-ns
}

function kubectx_install() {
  echo "\e[31minstalling kubectx\e[0m"
  $(find $HOME -iname krew -type f) install ctx
  add_to_profile kubectx 'alias kctx="kubectl ctx"'
  kubectl plugin list | grep kubectl-ctx
}

function netshoot_install() {
  echo "\e[31minstalling netshoot\e[0m"
  $(find $HOME -iname krew -type f) index add netshoot https://github.com/nilic/kubectl-netshoot.git || echo index already added
  $(find $HOME -iname krew -type f) install netshoot/netshoot
  kubectl netshoot completion bash >completion_netshoot
  mv -f completion_netshoot $COMPLETION_FOLDER/netshoot
  add_to_profile netshoot "alias netshoot='k netshoot run tmp'
source $COMPLETION_FOLDER/netshoot"
  kubectl plugin list | grep kubectl-netshoot
}

function k9s_install() {
  echo "\e[31minstalling k9s\e[0m"
  wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
  apt install -y --fix-missing ./k9s_linux_amd64.deb
  rm ./k9s_linux_amd64.deb
  k9s completion bash >completion_k9s
  mv -f completion_k9s $COMPLETION_FOLDER/k9s
  add_to_profile k9s "source $COMPLETION_FOLDER/k9s
alias kd=k9s"

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
  $(find $HOME -iname krew -type f) install neat
  kubectl plugin list | grep kubectl-neat
}

function yq_install() {
  echo "\e[31minstalling yq\e[0m"
  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
  yq completion bash >completion_yq
  mv -f completion_yq $COMPLETION_FOLDER/yq
  add_to_profile yq "source $COMPLETION_FOLDER/yq"
  yq --version
}

function ccat_install() {
  echo "\e[31minstalling ccat\e[0m"
  vversion=$(curl https://api.github.com/repos/batmac/ccat/releases | jq '.[0].tag_name' | sed 's/"//g')
  version=$(echo $vversion | sed 's/v//g')
  wget https://github.com/batmac/ccat/releases/download/$vversion/ccat-$version-linux-amd64.tar.gz -O ccat.tar.gz
  tar -xvf ccat.tar.gz
  mv -f ccat /usr/local/bin
  rm ccat.tar.gz
  add_to_profile ccat "alias cat=ccat
alias _cat=/usr/local/bin/cat"

  ccat --version
}

function talosctl_install() {
  echo "\e[31minstalling talosctl\e[0m"
  curl -sL https://talos.dev/install | sh
  talosctl completion bash >completion_talosctl
  mv -f completion_talosctl $COMPLETION_FOLDER/talosctl
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
  /root/.local/bin/xxh +I xxh-plugin-prerun-dotfiles
  /root/.local/bin/xxh +I xxh-shell-bash
  /root/.local/bin/xxh +I xxh-plugin-prerun-xxh

  mkdir -p $HOME/.config/xxh
  echo 'hosts:
  ".*":
    +s: bash
    +I:
      - xxh-ishell-bash
      - xxh-plugin-bash-ohmybash
      - xxh-plugin-prerun-dotfiles' >$HOME/.config/xxh/config.xxhc

  add_to_profile xxh 'alias ssh=xxh
alias _ssh=/usr/bin/ssh'
}

function speedtest_install() {
  echo "\e[31minstalling speedtest\e[0m"
  add_to_profile speedtest 'alias speedtest="wget -O /dev/null https://proof.ovh.net/files/10Gb.dat"
alias fast=speedtest'
}

function operator_sdk_install() {
  echo "\e[31minstalling operator-sdk\e[0m"
  export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
  export OS=$(uname | awk '{print tolower($0)}')
  export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/latest/download/
  curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}
  chmod +x operator-sdk_${OS}_${ARCH}
  mv -f operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk

  operator-sdk completion bash >completion_operator_sdk
  mv -f completion_operator_sdk $COMPLETION_FOLDER/operator-sdk
  add_to_profile operator_sdk "source $COMPLETION_FOLDER/operator-sdk"
}

function argocd_install() {
  echo "\e[31minstalling argocd\e[0m"
  curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x argocd-linux-amd64
  mv -f argocd-linux-amd64 /usr/local/bin/argocd

  argocd completion bash >completion_argocd
  mv -f completion_argocd $COMPLETION_FOLDER/argocd
  add_to_profile argocd "source $COMPLETION_FOLDER/argocd"
}

function virtctl_install() {
  echo "\e[31minstalling virtctl\e[0m"

  $(find $HOME -iname krew -type f) install virt
  export VERSION=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
  wget https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64
  chmod +x virtctl-${VERSION}-linux-amd64
  mv -f virtctl-${VERSION}-linux-amd64 /usr/local/bin/virtctl

  virtctl completion bash >completion_virtctl
  mv -f completion_virtctl $COMPLETION_FOLDER/virtctl
  add_to_profile virtctl "source $COMPLETION_FOLDER/virtctl"
}

function neovim_install() {
  echo "\e[31minstalling neovim\e[0m"

  apt install -y ruby-full fzf ripgrep fd-find lua5.4 nodejs liblua5.4-0 liblua5.4-dev
  gem install neovim
  curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage
  chmod u+x nvim-linux-x86_64.appimage
  mv -f nvim-linux-x86_64.appimage /usr/local/bin/nvim

  rm -rf $HOME/.config/nvim
  git clone https://github.com/LazyVim/starter $HOME/.config/nvim
  rm -rf $HOME/.config/nvim/.git

  wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
  unzip JetBrainsMono.zip -d fonts
  mkdir -p $HOME/.local/share/fonts
  mv -f fonts/*.ttf $HOME/.local/share/fonts
  rm -rf fonts JetBrainsMono.zip

  wget https://luarocks.org/releases/luarocks-3.12.2.tar.gz
  tar zxpf luarocks-3.12.2.tar.gz
  pushd luarocks-3.12.2
  ./configure && make && make install
  luarocks install luasocket
  popd
  rm -rf luarocks-3.12.2 luarocks-3.12.2.tar.gz

  echo 'require("config.lazy")
vim.g.clipboard = "osc52"
vim.cmd(":set listchars=eol:$,tab:>-,trail:~,extends:>,precedes:<,space:⋅")
vim.cmd(":set nolist")' >$HOME/.config/nvim/init.lua

  echo "local opts = { noremap = true}

local function map_visual(shortcut, action)
  vim.keymap.set('v', shortcut, action, opts)
end
local function map_normal(shortcut, action)
  vim.keymap.set('n', shortcut, action, opts)
end

map_normal('<C-c>', function()
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  if #bufs > 1 then
    vim.cmd('bdelete')
  else
    vim.cmd('q')
  end
end)

local blink = require('blink.cmp')
blink.setup({
  keymap = {
    ['<C-l>'] = { 'cancel' },  -- cancel completion
  }
})

vim.keymap.set('i', '<C-l>', '<C-e>',{remap=true}) -- break completion
map_normal('<C-s>', ':w<CR>') -- save
map_normal('t', 'za') -- toggle section
vim.keymap.set('n', 'ku', 'gcc',{remap=true}) -- toggle comment
vim.keymap.set('v', 'ku', 'gc',{remap=true}) -- toggle comment
vim.keymap.set('n', 'kc', 'gcc',{remap=true}) -- toggle comment
vim.keymap.set('v', 'kc', 'gc',{remap=true}) -- toggle comment
map_normal('<C-f>', '/') -- search
map_normal('<C-y>', '<C-r>') -- redo
map_normal('<C-z>', 'u') -- undo
map_normal('<C-R>', [[:%s/\<<C-r><C-w>\>//gc<Left><Left><Left>]]) -- search and replace selected word
map_normal('<F2>', [[:%s/\<<C-r><C-w>\>//gc<Left><Left><Left>]]) -- search and replace selected word
vim.keymap.set('v', '<F2>', function()
  local sel_raw = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'))
  if #sel_raw > 1 then
    -- search and replace in selected text
    vim.api.nvim_input(':s///gc<Left><Left><Left><Left>')
  else
    -- search and replace selected single line text
    vim.api.nvim_input('\"hy:%s/<C-r>h//gc<Left><Left><left>')
  end
end)
vim.keymap.set('v', '<C-R>', function()
  local sel_raw = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'))
  if #sel_raw > 1 then
    -- search and replace in selected text
    vim.api.nvim_input(':s///gc<Left><Left><Left><Left>')
  else
    -- search and replace selected single line text
    vim.api.nvim_input('\"hy:%s/<C-r>h//gc<Left><Left><left>')
  end
end)

map_normal('6', '<C-w>l') -- switch to right window
map_normal('4', '<C-w>h') -- switch to left window
map_normal('8', ':bnext<CR>') -- switch to next tab #TODO
map_normal('2', ':bprevious<CR>') -- switch to previous tab #TODO
map_normal('<A-8>', '<cmd>resize +2<cr>')
map_normal('<A-2>', '<cmd>resize -2<cr>')
map_normal('<A-4>', '<cmd>vertical resize -2<cr>')
map_normal('<A-6>', '<cmd>vertical resize +2<cr>')
map_normal('<F11>',function()
  vim.opt.list = not vim.opt.list:get()
end) -- show hidden

-- Open file in a new window
vim.keymap.set('n', '<C-t>', function()
  vim.cmd('tabnew')
  require('telescope').extensions.file_browser.file_browser()
end, opts)

-- open file in new horizontal split
vim.keymap.set('n', '<A-T>', function()
  vim.cmd('split')
  require('telescope').extensions.file_browser.file_browser()
end, opts)

-- Open file in vertical split
vim.keymap.set('n', '<A-t>', function()
  vim.cmd('vsplit')
  require('telescope').extensions.file_browser.file_browser()
end, opts)" >$HOME/.config/nvim/lua/config/keymaps.lua

  echo 'return {
  {
    "LazyVim/LazyVim",
    keys = {
      {
        "<F12>",
        function()
          vim.o.paste = not vim.o.paste
          vim.notify("Paste mode: " .. (vim.o.paste and "ON" or "OFF"))
        end,
        desc = "Toggle paste mode",
      },
    },
  },
}' >$HOME/.config/nvim/lua/plugins/toggle-paste.lua

  echo 'return {
  "nvim-telescope/telescope-file-browser.nvim",
  dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
  config = function()
    require("telescope").load_extension("file_browser")
  end,
}' >$HOME/.config/nvim/lua/plugins/telescope-file-browser.lua

  echo 'return {
  {
    "someone-stole-my-name/yaml-companion.nvim",
    ft = { "yaml" },
    dependencies = {
      { "neovim/nvim-lspconfig" },
      { "nvim-lua/plenary.nvim" },
      { "nvim-telescope/telescope.nvim" },
    },
    config = function(_, opts)
      local cfg = require("yaml-companion").setup(opts)
      require("lspconfig")["yamlls"].setup(cfg)
      require("telescope").load_extension("yaml_schema")
    end,
  },
}' >$HOME/.config/nvim/lua/plugins/yaml-companion.lua

  echo 'return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = function(_, opts)
    opts.sections.lualine_z = {
      {
        function()
          local schema = require("yaml-companion").get_buf_schema(0)
          if schema.result[1].name == "none" then
            return ""
          end
          return schema.result[1].name
        end,
      },
      {
        function()
          return " " .. os.date("%R")
        end,
      },
    }
  end,
}' >$HOME/.config/nvim/lua/plugins/lualine.lua

  # open issue: https://github.com/LazyVim/LazyVim/issues/6039
  echo 'return {
  { "mason-org/mason.nvim", version = "^1.0.0" },
  { "mason-org/mason-lspconfig.nvim", version = "^1.0.0" },
}' >$HOME/.config/nvim/lua/plugins/mason-workaround.lua

  add_to_profile neovim "alias vim=nvim
git config --global core.editor nvim
export EDITOR=nvim
export VISUAL=nvim"
}

function chatgpt_install() {
  echo "installing chatgpt\e[0m"
  wget https://github.com/kardolus/chatgpt-cli/releases/latest/download/chatgpt-linux-amd64
  chmod +x chatgpt-linux-amd64
  mv chatgpt-linux-amd64 /usr/local/bin/chatgpt
  mkdir -p $HOME/.chatgpt-cli

  add_to_profile chatgpt "alias c=chatgpt
export OPENAI_MODEL=gpt-5-nano
export OPENAI_TRACK_TOKEN_USAGE=true
export OPENAI_ROLE='You are a seasoned tech veteran and cut right to the chase, no uneccessary output, minimalistic examples'"
}

function bitwarden_install() {
  echo "installing bitwarden\e[0m"
  snap install bw
  snap refresh
  wget https://github.com/bitwarden/sdk-sm/releases/download/bws-v1.0.0/bws-x86_64-unknown-linux-gnu-1.0.0.zip
  unzip bws-x86_64-unknown-linux-gnu-1.0.0.zip
  rm bws-x86_64-unknown-linux-gnu-1.0.0.zip
  mv bws /usr/local/bin/

  bws completions bash >completion_bitwarden
  mv -f completion_bitwarden $COMPLETION_FOLDER/bitwarden
  # set BWS_ACCESS_TOKEN in ~/.secure_vars !
  add_to_profile bitwarden "source $COMPLETION_FOLDER/bitwarden
export OPENAI_API_KEY=\$(bws secret list | yq e '.[] | select(.key == \"openai-api-key\") | .value')
export PASSWORD=\$(bws secret list | yq e '.[] | select(.key == \"password\") | .value')
export TF_VAR_password=\$PASSWORD"
}

function miscelanious_install() {
  echo "installing miscelanious\e[0m"
  apt install -y htop iotop net-tools tree lsd apache2-utils # apache2-utils => needed for htpasswd for argocd bcrypt

  echo 'set completion-ignore-case On' >>/etc/inputrc

  add_to_profile lsd 'alias ls=lsd
ll="lsd -l"'

  add_to_profile secure 'source ~/.secure_vars'

  add_to_profile git 'git config --global core.autocrlf false
git config --global core.eol lf
git config --global core.filemode false
alias gitwip="git add . && git commit -m wip && git pull --rebase && git push"
alias gitgud='"'"'_gitgud() { args="$@" && git add . && git commit -m "$args" && git pull --rebase && git push ;}; _gitgud'"'
alias gg=gitgud
alias gwip=gitwip"

  add_to_profile prompt 'WHITE="\[$(tput setaf 7)\]"
CYAN="\[$(tput setaf 3)\]"
MAGENTA="\[$(tput setaf 5)\]"
BLUE="\[$(tput setaf 6)\]"
GREEN="\[$(tput setaf 34)\]"
TIME=$CYAN'"'\T'"'
USER_HOST=$MAGENTA'"'\u@\h'"'
KUBECTL=$MAGENTA'"'"'$(kubectl config current-context)/$(kubectl config view --minify -o jsonpath='{..namespace}')'"'"'
CURRENT_PATH=$BLUE'"'\w'"'
export PS1="$WHITE[$TIME$WHITE]$WHITE[$USER_HOST$WHITE]$WHITE[$KUBECTL$WHITE]$CURRENT_PATH$WHITE: $GREEN"'

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
alias hist="history -a && history -r"
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
  #xxh_install
  speedtest_install
  operator_sdk_install
  argocd_install
  virtctl_install
  neovim_install
  chatgpt_install
  bitwarden_install
  miscelanious_install
}

install_tools
