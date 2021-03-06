# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure(2) do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://atlas.hashicorp.com/search.
  config.vm.box = "bento/ubuntu-18.04"

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  config.vm.provider "virtualbox" do |vb|
    # Forward GDB port
    # config.vm.network "forwarded_port", guest: 1234, host: 1234

    # Customize the amount of memory on the VM:
    vb.memory = "4096"
  end

  # Install rust osdev toolkit and some standard utilities
  # these run as user vagrant instead of root
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    sudo apt-get update
    sudo apt-get upgrade
    sudo apt-get autoremove
    sudo apt-get install python3 python3-dev python3-pip -y
    sudo apt-get install vim git nasm -y
    #sudo apt-get install xorriso -y
    sudo apt-get install texinfo flex bison python-dev ncurses-dev -y
    sudo apt-get install cmake libssl-dev -y

    python3 -m pip install --upgrade pip
    python3 -m pip install requests

    curl -sf https://raw.githubusercontent.com/phil-opp/binutils-gdb/rust-os/build-rust-os-gdb.sh | sh

    curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain nightly -y

    export PATH="$HOME/.cargo/bin:$PATH"
    rustup component add rust-src
    cargo install --force xargo

    echo "export PATH="$HOME/.cargo/bin:$PATH"; cd /vagrant" >> $HOME/.bashrc
  SHELL
end
