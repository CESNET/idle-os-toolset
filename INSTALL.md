### Installation and Setup

All data and files related to this project (toolset code, VM definitions, traffic captures, etc.) are stored under a single directory, which will also be used as the home directory of the `vmuser` user. In the examples below we use `/data/virtual_machines` as that directory; if you prefer a different location, replace `/data/virtual_machines` with your own path consistently.

Optionally, define an environment variable to refer to this directory more easily:

Ubuntu and Oracle Linux:
```bash
export TOOLSET_ROOT=/data/virtual_machines   # change this if you use a different root path
```

#### 1. Create new user
Create the `vmuser` user (without a password). The home directory of `vmuser` must be the directory where you want to store everything related to this project (toolkit files, virtual machines, traffic captures, etc.). This directory must match the value you chose for `TOOLSET_ROOT`. To allow switching to `vmuser` without a password using `su`, modify PAM so that `vmuser` is exempt from authentication.

Ubuntu and Oracle Linux:
```bash
sudo useradd -d "$TOOLSET_ROOT" -s /bin/bash vmuser
sudo chown -R vmuser:vmuser "$TOOLSET_ROOT"

sudo sed -i '1iauth sufficient pam_succeed_if.so user = vmuser' /etc/pam.d/su
```

#### 2. Create virtual environment
Ubuntu and Oracle Linux:
```bash
python -m venv ${TOOLSET_ROOT}/venv
source ${TOOLSET_ROOT}/venv/bin/activate
```

#### 3. Add activating of `venv` after switching user to `vmuser`
Ubuntu and Oracle Linux:
```bash
# switch to vmuser
su - vmuser
```
Append this to the end of ~/.bashrc (create it if it doesn't exist)
```bash
VENV="$HOME/venv"

if [ -f "$VENV/bin/activate" ]; then
    source "$VENV/bin/activate"
fi
```

Check if ~/.bash_profile exists; if not, create this file and append
```bash
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
```

The virtual environment should now be activated automatically every time you switch to `vmuser`.


#### 4. Install VirtualBox, Extension Pack, Vagrant and utilities

Ubuntu:
```bash
apt install jq unzip p7zip-full arp-scan

wget "https://download.virtualbox.org/virtualbox/7.2.6/virtualbox-7.2_7.2.6-172322~Ubuntu~jammy_amd64.deb"
apt install ./virtualbox-7.2_7.2.6-172322~Ubuntu~jammy_amd64.deb

wget "https://download.virtualbox.org/virtualbox/7.2.6/Oracle_VirtualBox_Extension_Pack-7.2.6.vbox-extpack"
VBoxManage extpack install "Oracle_VirtualBox_Extension_Pack-7.2.6.vbox-extpack"

wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
apt update && sudo apt install vagrant
```

Oracle Linux:
```bash
yum install jq
yum install oraclelinux-developer-release-*

yum install VirtualBox-7.1

sudo dnf install kernel-uek-devel-$(uname -r)
sudo /sbin/vboxconfig

wget https://download.virtualbox.org/virtualbox/7.2.8/Oracle_VirtualBox_Extension_Pack-7.2.8.vbox-extpack
sudo VBoxManage extpack install --replace Oracle_VirtualBox_Extension_Pack-7.2.8.vbox-extpack

# install vagrant
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install vagrant
```

#### 5. Install Python dependencies

Install the Python packages required by the scripts:

- `pyshark, pandas and tshark`: for processing network traffic captures and applying HTTP filters.
- `litellm`: for sending requests to the LLM provider (for example, Groq) used to classify or enrich OS information.
- `python3-tk` (`python3-tkinter`): to enable the graphical interface used by some scripts.
- `python-is-python3`: to have the `python` command point to Python 3.
- `paramiko and pywinrm`: used to connect via SSH/WinRM to VMs created from images and retrieve their OS information.

Ubuntu:
```bash
pip install pyshark litellm pandas paramiko pywinrm
apt install -y python3-tk python-is-python3 tshark
```

Oracle Linux:
```bash
pip install pyshark litellm pandas
dnf install -y python3-tkinter wireshark
```

In the `get_os_info.py` file you will find a template for the requests that use the Groq model. You must insert your API key in the corresponding environment variable. If you use a different model or provider, update both the model configuration and the environment variable name to match your new provider.

#### 6. Install NEMEA and ipfixprobe

The toolkit can integrate with `ipfixprobe` and NEMEA to process IPFIX/flow records. Install the required build dependencies and compile the tools as follows:

Ubuntu:
```bash
apt-get install -y gawk bc autoconf automake gcc g++ libtool libxml2-dev make pkg-config libpcap-dev libidn11-dev bison flex

cd "$TOOLSET_ROOT"

git clone --recursive https://github.com/CESNET/nemea
cd nemea

./bootstrap.sh
./configure
make
make install


apt install git make cmake g++ pkg-config rpm
apt install libunwind-dev liblz4-dev libssl-dev libfuse3-dev libatomic1

cd ..
git clone https://github.com/CESNET/ipfixprobe.git

cd ipfixprobe
mkdir build && cd build

mkdir -p /usr/bin/nemea/
ln -s /usr/local/bin/ur_processor.sh /usr/bin/nemea/ur_processor.sh

cmake .. -DENABLE_NEMEA=ON -DENABLE_INPUT_PCAP=ON -DENABLE_OUTPUT_UNIREC=ON
make -j"$(nproc)"
make install

cd ..
```

Oracle Linux:
```bash
yum install -y bc autoconf automake gcc gcc-c++ libtool libxml2-devel make pkg-config libpcap-devel libidn-devel bison flex

cd "$TOOLSET_ROOT"

git clone --recursive https://github.com/CESNET/nemea
cd nemea

./bootstrap.sh
./configure
make
make install


dnf install epel-release git make cmake gcc-c++ rpm-build
dnf install libunwind-devel lz4-devel openssl-devel fuse3-devel
dnf install gcc-toolset-14-libatomic-devel
dnf install libatomic

cd ..
git clone https://github.com/CESNET/ipfixprobe.git

cd ipfixprobe
mkdir build && cd build

mkdir -p /usr/bin/nemea/
ln -s /usr/local/bin/ur_processor.sh /usr/bin/nemea/ur_processor.sh

cmake .. -DENABLE_NEMEA=ON -DENABLE_INPUT_PCAP=ON -DENABLE_OUTPUT_UNIREC=ON
make -j"$(nproc)"
make install

cd ..
```

After this step, `ipfixprobe` and the NEMEA components will be available system-wide and can be used together with the scripts to process captured traffic.


#### 7. Install latest Nmap version

Nmap uses a fingerprint database to detect a host's operating system. Newer versions have more up-to-date fingerprints, so it's necessary to build from source to get the latest release instead of the outdated one in the distro repositories:

Ubuntu:
```bash
wget https://nmap.org/dist/nmap-7.99.tar.bz2 -O nmap-7.99.tar.bz2
bzip2 -cd nmap-7.99.tar.bz2 | tar xvf -
cd nmap-7.99
./configure
make
su root
make install
```

Nmap is run against the VMs over a VirtualBox host-only network, so the `vboxnet0` interface must exist before scanning. Create it as `vmuser`:

```bash
su - vmuser -c "VBoxManage hostonlyif create"
```

#### 8. Create data directories and set permissions

Create the data directory structure where all files related to these scripts will be stored, and give `vmuser` read and write permissions:

Ubuntu and Oracle Linux:
```bash
mkdir -p "$TOOLSET_ROOT"/vagrant/
mkdir -p "$TOOLSET_ROOT"/traffic/
mkdir -p "$TOOLSET_ROOT"/vm_info/
mkdir -p "$TOOLSET_ROOT"/os_info/
mkdir -p "$TOOLSET_ROOT"/vm_images/
mkdir -p "$TOOLSET_ROOT"/nmap/


chown -R vmuser:vmuser "$TOOLSET_ROOT"/

usermod -aG virtualbox vmuser
```

After this step, `vmuser` will own the entire project root directory and will belong to the `virtualbox` group, which allows it to manage VirtualBox virtual machines properly.

#### 9. Install Android communication tools

To communicate with Android virtual machines and devices, install the following:

Ubuntu:
```bash
apt install android-tools-adb

su - vmuser -c "vagrant plugin install vagrant-dummy-communicator"
```

Oracle Linux:
```bash
dnf install -y android-tools

su - vmuser -c "vagrant plugin install vagrant-dummy-communicator"
```

#### 10. Make shell scripts executable

Finally, give execution permissions to all shell scripts in the `scripts` directory:

Ubuntu and Oracle Linux:
```bash
chmod +x "$TOOLSET_ROOT"/scripts/*.sh
```

At this point, the environment should be ready to use the toolkit scripts in both CLI and GUI modes.

#### 11. Add GROQ API key
Add your GROQ API key to `.env.example`, then rename it to `.env`.

#### 12. Install all virtual machines
Once the environment is set up, you can install all the virtual machines listed in `vm_list.csv` at once by running `create_vms.sh`:

```bash
cd "$TOOLSET_ROOT"/scripts
./create_vms.sh
```

This reads each entry in `vm_list.csv` and creates the corresponding VM.

> **Note:** `create_vms.sh` also triggers automatic OS fingerprinting via `gpt-oss-120b` and `gpt-oss-20b` model on GROQ. Depending on how many machines are listed in `vm_list.csv`, the free token quota may or may not be enough to fingerprint all of them in a single run; if both models' quotas end up exhausted, the remaining requests will start failing. If this happens, stop the loop at that point and wait for the token quota to reset before resuming fingerprinting for the rest of the machines. 

