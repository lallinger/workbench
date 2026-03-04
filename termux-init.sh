pushd $HOME
cp -rT storage/downloads/home/ .
apt install -y git
pushd gitops
git pull
popd
pushd talos
git pull
popd
pushd workbench/
chmod +x ./setup.sh
./setup.sh
