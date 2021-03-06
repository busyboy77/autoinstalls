#cloud-config
autoinstall:
  version: 1
  early-commands:
    - systemctl stop ssh # otherwise packer tries to connect and exceed max attempts
  network:
    network:
      version: 2
      ethernets:
        eth0:
          dhcp4: true
          dhcp-identifier: mac


  ## the storage options are -- 1 disk /dev/vda with GPT partitioning
  ## 4 paritions  -- 1: bios_grub (1mb), 2: /boot (1GB), 3: swap (4GB) , 4: / with all remaining space -- all XFS
  storage:
    config:
    - ptable: gpt
      path: /dev/vda
      wipe: superblock-recursive
      preserve: false
      name: ''
      grub_device: true
      type: disk
      id: diskvda
    - device: diskvda         #bois_grub parition no need for format and mount
      size: 1048576
      flag: bios_grub
      number: 1
      preserve: false
      grub_device: false
      type: partition
      id: partition0
    - device: diskvda        #/boot parition
      wipe: superblock
      flag: ''
      number: 2
      size: 1G
      preserve: false
      grub_device: false
      type: partition
      id: partition2
    - fstype: xfs        #/boot format
      volume: partition2
      preserve: false
      type: format
      id: format1
    - path: /boot        #/boot mount
      device: format1
      type: mount
      id: mount1
#    - device: diskvda   #swap partition
#      size: 4G
#      wipe: superblock
#      flag: swap
#      number: 3
#      preserve: false
#      grub_device: false
#      type: partition
#      id: partition3
#    - fstype: swap     #swap format
#      volume: partition3
#      preserve: false
#      type: format
#      id: format2
#    - path: ''         #swap mount
#      device: format2
#      type: mount
#      id: mount2
    - device: diskvda         #root partition
      size: -1
      wipe: superblock
      flag: ''
      number: 4
      preserve: false
      grub_device: false
      type: partition
      id: partition1
    - fstype: xfs             #root format
      volume: partition1
      preserve: false
      type: format
      id: format0
    - path: /                 #root mount
      device: format0
      type: mount
      id: mount0
    swap: {swap: 0}
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:  # This is section you may want to add to interactive-sections  (user name and password are ubuntu here)
    hostname: devops
    password: "$6$exDY1mhS4KUYCE/2$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0"
    username: ubuntu
  ssh:
    allow-pw: true
    install-server: true
  apt:
    sources:
      ignored1:  # This is here to get the yaml formatting right when adding a ppa
        source: ppa:graphics-drivers/ppa
  packages:
    - build-essential
    - network-manager
    - dkms
    - emacs-nox
    - apt-transport-https
    - ca-certificates
    - curl
    #- ubuntu-desktop-minimal^
  package_update: true
  package_upgrade: true
  late-commands:
    # Changing from networkd to NetworkManager
    # move existing config out of the way
    - find /target/etc/netplan/ -name "*.yaml" -exec sh -c 'mv "$1" "$1-orig"' _ {} \;
    # Create a new netplan and enable it
    - |
      cat <<EOF | sudo tee /target/etc/netplan/01-netcfg.yaml
      network:
        version: 2
        renderer: NetworkManager
      EOF
    - curtin in-target --target /target netplan generate
    - curtin in-target --target /target netplan apply
    - curtin in-target --target /target systemctl enable NetworkManager.service
    # Enable the KVM Console for virsh console
    - curtin in-target --target /target systemctl enable serial-getty@ttyS0.service
    - curtin in-target --target /target systemctl start serial-getty@ttyS0.service
    # Write a script that can take care of some post install setup "late-commands" cannot be interactive unfortunately"
    # - |
    #   cat <<EOF | sudo tee /target/etc/finish-install-setup.sh
    #   #!/usr/bin/env bash
    #   echo *************************
    #   echo ****  Finish Setup   ****
    #   echo *************************
    #   echo 'Enter the hostname for this system: '
    #   read NEW_HOSTNAME
    #   hostnamectl set-hostname \${NEW_HOSTNAME}
    #   echo
    #   echo 'Enter the timezone for this system: '
    #   echo 'America/Los_Angeles America/Denver America/Chicago America/New_York'
    #   read NEW_TIMEZONE
    #   timedatectl set-timezone \${NEW_TIMEZONE}
    #   echo *************************
    #   echo
    #   echo *************************
    #   echo 'Restarting to finish ...'
    #   shutdown -r 3
    #   EOF
    # - curtin in-target --target /target chmod 744 /etc/finish-install-setup.sh
    ## This is creating a script which will run after the installation is completed successfully and then installs docker and docker-compose using recommended method by docker, inc.

    - |
      cat <<EOF | sudo tee /target/etc/finish-install-setup.sh
      apt-get remove docker docker-engine docker.io containerd runc --yes
      apt-get install     ca-certificates     curl     gnupg     lsb-release --yes
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo   "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu  \$(lsb_release -cs) stable" >  /etc/apt/sources.list.d/docker.list
      apt-get update
      echo -e "overlay\nbr_netfilter" > /etc/modules-load.d/containerd.conf
      sudo modprobe overlay
      sudo modprobe br_netfilter
      echo -e "net.bridge.bridge-nf-call-iptables  = 1\nnet.ipv4.ip_forward                 = 1\nnet.bridge.bridge-nf-call-ip6tables = 1" >/etc/sysctl.d/99-kubernetes-cri.conf
      sudo sysctl --system
      apt-get install containerd.io --yes
      mkdir -p /etc/containerd
      containerd config default>/etc/containerd/config.toml
      sudo systemctl restart containerd
      sudo systemctl enable containerd
      systemctl mask swap.target
      sudo apt-get update
      sudo apt-get install -y kubelet kubeadm kubectl rpcbind nfs-common
      systemctl enable iscsid
      systemctl start iscsid
      sudo apt-mark hold kubelet kubeadm kubectl
      reboot
      EOF
    - curtin in-target --target /target chmod 744 /etc/finish-install-setup.sh
    #- ls -l > /target/root/ls.out
    #- pwd > /target/root/pwd.out
    #- mount > /target/root/mount.out
    #- touch afile
    #- cp afile /target/root/
    #- ls -l / > /target/root/ls-root.out
    #- ls -l /target > /target/root/ls-target.out
    #- ls -l /target/cdrom > /target/root/ls-target-cdrom.out
    # - curtin in-target --target=/target -- apt-get --purge -y --quiet=2 remove apport bcache-tools btrfs-progs byobu cloud-guest-utils cloud-initramfs-copymods
    # - curtin in-target --target=/target -- apt-get --purge -y --quiet=2 remove cloud-initramfs-dyn-netconf friendly-recovery fwup landscape-common lxd-agent-loader
    # - curtin in-target --target=/target -- apt-get --purge -y --quiet=2 remove ntfs-3g open-vm-tools plymouth plymouth-theme-ubuntu-text popularity-contest rsync screen snapd sosreport tmux ufw
    # - curtin in-target --target=/target -- apt-get --purge -y --quiet=2 autoremove
    # - curtin in-target --target=/target -- apt-get clean
    # - sed -i 's/ENABLED=1/ENABLED=0/' /target/etc/default/motd-news
    # - sed -i 's|# en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /target/etc/locale.gen
    # - curtin in-target --target=/target -- locale-gen
    # - ln -fs /dev/null /target/etc/systemd/system/connman.service
    # - ln -fs /dev/null /target/etc/systemd/system/display-manager.service
    # - ln -fs /dev/null /target/etc/systemd/system/motd-news.service
    # - ln -fs /dev/null /target/etc/systemd/system/motd-news.timer
    # - ln -fs /dev/null /target/etc/systemd/system/plymouth-quit-wait.service
    # - ln -fs /dev/null /target/etc/systemd/system/plymouth-start.service
    # - ln -fs /dev/null /target/etc/systemd/system/systemd-resolved.service
    # - ln -fs /usr/share/zoneinfo/Europe/Kiev /target/etc/localtime
    # - rm -f /target/etc/resolv.conf
    # - printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\noptions timeout:1\noptions attempts:1\noptions rotate\n' > /target/etc/resolv.conf
    ## Complete disable snapd -- Add # infront of all line below to enable.
    - rm -f /target/etc/update-motd.d/10-help-text
    - rm -rf /target/root/snap
    - rm -rf /target/snap
    - rm -rf /target/var/lib/snapd
    - rm -rf /target/var/snap
    ##Unlock the password of the named account. This option re-enables a password by changing the password back to its previous value (to the value before using the -l option).
    - curtin in-target --target=/target -- passwd -q -u root
    ##Passing the number -1 as MAX_DAYS will remove checking a password's validity.
    - curtin in-target --target=/target -- passwd -q -x -1 root
    ##Immediately expire an account's password. This in effect can force a user to change their password at the user's next login.
    # - curtin in-target --target=/target -- passwd -q -e root
    - sed -i 's|^root:.:|root:$1$pKOIPVsj$UrAMDq7ItupfgbMoPJoL91:|' /target/etc/shadow # set the root password to 1
    # - curtin in-target --target=/target -- passwd -q -e root
    - sed -i 's|^ubuntu:.:|ubuntu:$1$pKOIPVsj$UrAMDq7ItupfgbMoPJoL91:|' /target/etc/shadow # set the root password to 1
    # Allow the ubuntu user to run arbitrary commands without being asked for password
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
    # Adds several options
    ## net.ifnames=0 ipv6.disable=1 biosdevname=0 -- maintains the older device names like eth0...ethN
    ## cgroup_enable=memory swapaccount=1 -- disables the docker's warning for swap usage.
    - sed -ie 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="net.ifnames=0 ipv6.disable=1 biosdevname=0 cgroup_enable=memory swapaccount=1"/' /target/etc/default/grub
    - curtin in-target --target=/target -- update-grub2
    # this removes the swap.img from fstab
    - swapoff -a
    - sed -ie '/\/swap.img/s/^/#/g' /target/etc/fstab
    ## unknown -- just keeping them for reference
    - curl -vo /target/usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    - |
      cat <<EOF |  tee /target/etc/modules-load.d/k8s.conf
      br_netfilter
      EOF
    - |
      cat <<EOF | sudo tee /target/etc/sysctl.d/k8s.conf
      net.bridge.bridge-nf-call-ip6tables = 1
      net.bridge.bridge-nf-call-iptables = 1
      EOF
    - sysctl --system
    - echo 'deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | tee /target/etc/apt/sources.list.d/kubernetes.list
  user-data: # Commands here run during first boot (cannot be interactive)
    disable_root: false
    package_upgrade: true
    timezone: Asia/Karachi
    runcmd:
      # Install the NVIDIA driver from the ppa we setup earlier
      - [apt-get, update]
      - [apt-get, dist-upgrade, --yes]
      - [apt, autoremove, --yes]
      - [bash, -x, /etc/finish-install-setup.sh ]
      # - [apt-get, install, --yes,  nvidia-driver-470] #, --no-install-recommends]
      # - [sudo, -u, ubuntu, dbus-launch, gsettings, set, org.gnome.desktop.background, picture-uri, file:///usr/share/backgrounds/Puget_Systems.png]
      - |
        #!/usr/bin/env bash
        echo ''
        echo '***************************************'
        echo ' To complete install setup please run, '
        echo ' sudo /etc/finish-install-setup.sh'
        echo '***************************************'
        echo ''
