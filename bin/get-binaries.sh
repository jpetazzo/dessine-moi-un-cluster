#!/bin/sh

# Get etcd and etcdctl
curl -L https://github.com/etcd-io/etcd/releases/download/v3.3.10/etcd-v3.3.10-linux-amd64.tar.gz |
  tar --strip-components=1 --wildcards -zx '*/etcd' '*/etcdctl'

# Get hyperkube (the metabinary that holds all the Kubernetes binaries!)
curl -L https://dl.k8s.io/v1.13.0/kubernetes-server-linux-amd64.tar.gz | 
  tar --strip-components=3 -zx kubernetes/server/bin/hyperkube

# Create a bunch of symlinks for convenience
for BINARY in kubectl kube-apiserver kube-scheduler kube-controller-manager kubelet kube-proxy;
do
  ln -s hyperkube $BINARY
done

# Get docker
curl -L https://download.docker.com/linux/static/stable/x86_64/docker-18.09.0.tgz |
  tar --strip-components=1 -zx
