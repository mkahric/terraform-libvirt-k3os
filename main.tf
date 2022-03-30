terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  #uri = "qemu+ssh:/user/kvmhost/system"
  uri = "qemu:///system"
}

resource "libvirt_pool" "k3os" {
  name = "k3os"
  type = "dir"
  path = "/srv/libvirt/images"
}

resource "libvirt_volume" "k3os-kernel" {
  name = "k3os-vmlinuz-amd64"
  format = "raw"
  pool = libvirt_pool.k3os.name
  source = "https://github.com/rancher/k3os/releases/download/v0.21.5-k3s2r1/k3os-vmlinuz-amd64"
}

resource "libvirt_volume" "k3os-initrd" {
  name = "k3os-initrd-amd64"
  format = "raw"
  pool = libvirt_pool.k3os.name
  source = "https://github.com/rancher/k3os/releases/download/v0.21.5-k3s2r1/k3os-initrd-amd64"
}

resource "libvirt_volume" "k3os-iso" {
  name = "k3os-amd64.iso"
  format = "iso"
  pool = libvirt_pool.k3os.name
  source = "https://github.com/rancher/k3os/releases/download/v0.21.5-k3s2r1/k3os-amd64.iso"
}

resource "libvirt_volume" "k3os-img" {
  name = "k3os.qcow2"
  size = 4294967296
  format = "qcow2"
  pool = libvirt_pool.k3os.name
}
resource "libvirt_network" "k3os-net" {
  name = "k3os"
  mode = "bridge"
  bridge = "br0"
}

resource "libvirt_domain" "k3os-vm" {
  name = "k3os"
  memory = "2048"
  vcpu = 1
  boot_device {
    dev = ["hd"]
  }
  disk {
    volume_id = libvirt_volume.k3os-img.id
  }
  disk {
    file = libvirt_volume.k3os-iso.id
  }
  kernel = libvirt_volume.k3os-kernel.id
  initrd = libvirt_volume.k3os-initrd.id
  cmdline = [
    {
      "k3os.fallback_mode" = "install"
      "k3os.install.config_url" = "http://192.168.229.129/config.yaml"
      "k3os.install.device" = "/dev/vda"
      "k3os.install.silent" = "true"
    }
  ]
  network_interface {
    network_id = libvirt_network.k3os-net.id
    wait_for_lease = true
  }
  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }
  console {
    type = "pty"
    target_type = "virtio"
    target_port = "1"
  }
  graphics {
    type        = "vnc"
    listen_type = "address"
    listen_address = "0.0.0.0"
  }
  provisioner "local-exec" {
    command = <<-EOT
      sleep 120
      curl -ks https://${libvirt_domain.k3os-vm.network_interface.0.addresses.0}:6443/ping || exit 1
      ssh -o StrictHostKeyChecking=no -i ${pathexpand("~/.ssh")}/id_ed25519 \
      rancher@${libvirt_domain.k3os-vm.network_interface.0.addresses.0} \
      cat /etc/rancher/k3s/k3s.yaml > ${pathexpand("~/.kube")}/config
      sed -i -e 's/127.0.0.1/${libvirt_domain.k3os-vm.network_interface.0.addresses.0}/' \
      ${pathexpand("~/.kube")}/config
    EOT
  }
}

output "k3os_node_ip_addr" {
  value = libvirt_domain.k3os-vm.network_interface.0.addresses.0
}
