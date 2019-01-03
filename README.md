# Dessine-moi un cluster

In december 2018, there were [4000 Certified Kubernetes Administrators](https://twitter.com/CloudNativChris/status/1072539903169310723).
I'm now one of them (yay!) and while preparing the certification, I wanted to understand better how the Kubernetes control plane works.
I tinkered a bit with [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way/), but I also wanted to
get a simpler, easier setup. This is what I came up with.

*This will NOT tell you how to set up a "production-ready" Kubernetes cluster.
This will show you how to set up a very simplified Kubernetes cluster,
taking many shortcuts in the process (for instance, the first iteration
gets you a 1-node cluster!) but giving a lot of space for further experimentation.*

TL,DR: this is for learning and educational purposes only!


## Get ALL THE BINARIES

First things first: we need a bunch of binaries. Specifically:
- etcd
- Kubernetes
- Docker (or some other container engine)

If you are already on the machine where you want to build your
cluster, I suggest placing all these binaries in `/usr/local/bin/`.
If you are going to do it on another machine, I suggest downloading
all the binaries to a `bin/` directory, then later copying that
directory to the target machine.


### etcd

Get binaries from the [etcd release page]. Pick the tarball for Linux amd64.
In that tarball, we just need `etcd` and (just in case) `etcdctl`.

This is a fancy one-liner to download the tarball and extract just what
we need:

```bash
curl -L https://github.com/etcd-io/etcd/releases/download/v3.3.10/etcd-v3.3.10-linux-amd64.tar.gz | 
  tar --strip-components=1 --wildcards -zx '*/etcd' '*/etcdctl'
```


### Kubernetes

Then, get binaries from the [kubernetes release page]. We want the "server"
bundle for adm64 Linux.

In that tarball, we just need one file: `hyperkube`.

It is a kind of meta-binary that contains all other binaries (API server,
scheduler, kubelet, kubectl...), a bit like `busybox`, if you will.

This is a fancy one-liner to download the bundle and extract hyperkube:

```bash
curl -L https://dl.k8s.io/v1.13.0/kubernetes-server-linux-amd64.tar.gz | 
  tar --strip-components=3 -zx kubernetes/server/bin/hyperkube
```

For convenience, create a handful of symlinks. This is not strictly
necessary, but if we don't, we will have to prefix every command with
`hyperkube`, for instance `hyperkube kubectl get nodes`.

```bash
for BINARY in kubectl kube-apiserver kube-scheduler kube-controller-manager kubelet kube-proxy;
do
  ln -s hyperkube $BINARY
done
```


### Docker

And then, we need Docker (or another runtime). Let's get one more tarball:

```bash
curl -L https://download.docker.com/linux/static/stable/x86_64/docker-18.09.0.tgz |
  tar --strip-components=1 -zx
```

ALRIGHT!

Let's get this cluster started.


## Root of all evil

We'll do everything as root for now.

Yes, it's ugly! But our goal is to set things up one at a time.

Get root, fire up tmux. We are going to use it as a crude
process manager and log monitor. Yes, it's ugly! But ... etc.

Start `etcd`:

```bash
etcd
```

That's it, we have a one-node etcd cluster.

Create a new pane in tmux (`Ctrl-b c`).

Start the API server:

```bash
kube-apiserver --etcd-servers http://localhost:2379
```

Congratulations, we now have a zero-node Kubernetes cluster! (Kind of.)

Let's take a moment to reflect on the output of these commands:

```bash
kubectl get all
kubectl get nodes
kubectl get componentstatuses
```

Alright, maybe we could try to run a Deployment?

```bash
kubectl create deployment web --image=nginx
```

If we check with `kubectl get all`, the Deployment has been created,
but nothing else happens. Because the code responsible for managing
deployments (and creating replica sets and pods etc.) is not running yet.

Let's start it!

```bash
kube-controller-manager --master http://localhost:8080
```

Create a new tmux pane (`Ctrl-b c` again), and look at resources and
events (with `kubectl get events`). We see a problem related to service
account "default".

We didn't indicate that we wanted a service account, but it has been
automatically added by the ServiceAccount admission controller.

We have two options:

1. Restart the API server with `--disable-admission-plugins=ServiceAccount`
2. Edit our Deployment spec to add `automountServiceAccountToken: false`

After doing one or the other, `kubectl get all` will show you that a pod
has been created, but it is still Pending. Why?

Because we don't have a scheduler yet. And, most importantly... we don't
even have a node!

So let's start the Docker Engine.

```bash
dockerd
```

That's it! Then, create a new tmux pane. (`Ctrl-b c` one more time.)

If you want, test that Docker really works:

```bash
docker run alpine echo hello
```

Now we can start kubelet. If we start kubelet "as is," it will work,
but it won't connect to the API server and it won't join our cluster.
This will be a bit more complicated than for the controller manager
(we can't just pass a `--master` flag to Kubelet). We need to give it
a `kubeconfig` file.

This `kubeconfig` file has exactly the same format as the one we
use when connecting to a Kubernetes API server. We can create it
with `kubectl config` commands:

```bash
kubectl --kubeconfig kubeconfig.kubelet config set-cluster localhost --server http://localhost:8080
kubectl --kubeconfig kubeconfig.kubelet config set-context localhost --cluster localhost
kubectl --kubeconfig kubeconfig.kubelet config use-context localhost
```

Now we can *really* start kubelet, passing it this kubeconfig file.

```bash
kubelet --kubeconfig kubeconfig.kubelet
```

If we create a new tmux pane (do you remember how? ☺) and run
`kubectl get nodes`, our node shows up. Great!

But if we look at our pod with `kubectl get pod`, it is still Pending.

Why?

Because there is no scheduler to decide where it should go. Sure, that
might seem weird, since there is only one node anyway (and the pod has
nowhere to go, nowhere to hide!), but keep in mind that the scheduler
also checks for various constraints. We might very well have only one
node, but the pod might not be allowed to run there, because the node is
full, or doesn't satisfy some other constraint.

We have two options here.

1. Manually assign the pod to our node.
2. Start the scheduler.

Option 1 would require us to export the YAML definition of the pod,
and recreate it after adding `nodeName: XXX` to its spec. (We cannot
just `kubectl edit` the pod, because `nodeName` is not a mutable field.)

Option 2 is simpler. All we have to do is:

```bash
kube-scheduler --master http://localhost:8080
```

Note that we could also run `kube-scheduler --kubeconfig kubeconfig.kubelet`
and it would have the same result, since (at this point) `kubeconfig.kubelet`
contains information saying "the API server is at `http://localhost:8080`."

What's next?

Well, running NGINX is great, but connecting to it is better.

First, to make sure that we're in good shape, we can get the IP address
of the NGINX pod with `kubectl get pods -o wide`, and `curl` that IP address.
This should get us the "Welcome to NGINX" page.

Then, we are going to create a `ClusterIP` service to obtain a stable IP
address (and load balancer) for our deployment.

```bash
kubectl expose deployment web --port=80
```

Get the service address that was allocated:

```bash
kubectl get svc web
```

And try to access it with `curl`. Unfortunately, it will time out.

To access service addresses, we need to run `kube-proxy`. It is similar
to other cluster components that we started earlier.

```bash
kube-proxy --master http://localhost:8080
```

We can now open a new pane in tmux, and if we `curl` that service
IP, it should get us to the NGINX page.

How did we get there? Ah, we can dive into `iptables` to get an idea.

```bash
iptables -t nat -L OUTPUT
```

This will show us that all traffic goes through a chain called `KUBE-SERVICES`.
Let's have a look at it.

```bash
iptables -t nat -L KUBE-SERVICES
```

In that chain, there should be two more sub-chains called `KUBE-SVC-XXX...`,
one for the `kubernetes` service (which corresponds to the API server itself)
and another for our `web` service.

If we look at that chain with `iptables -t nat -L KUBE-SVC-XXX...`, it
sends traffic to another sub-chain called `KUBE-SEP-YYY...`. SEP stands for
"**S**ervice **E**nd**P**oint". If we look at that chain, we will see an
iptables rule that `DNAT`s traffic to our container.

If you wonder how `kube-proxy` load balances traffic between pods, try
the following experiment. First, scale up our Deployment.

```bash
kubectl scale deployment web --replicas=4
```

Wait until all the pods are running. Then, look at the `KUBE-SVC-XXX...`
chain from earlier. It will look like this:

```
Chain KUBE-SVC-BIJGBSD4RZCCZX5R (1 references)
target     prot opt source               destination         
KUBE-SEP-ESTRSP6725AF5NCN  all  --  anywhere             anywhere             statistic mode random probability 0.25000000000
KUBE-SEP-VEPQL5BTFC5ANBYK  all  --  anywhere             anywhere             statistic mode random probability 0.33332999982
KUBE-SEP-7G72APUFO7T3E33L  all  --  anywhere             anywhere             statistic mode random probability 0.50000000000
KUBE-SEP-ZSGQYP5GSBQYQECF  all  --  anywhere             anywhere            
```

Each time a new connection is made to the service IP address, it goes
through that chain, and each rule is examined in order. The first
rule is using probabilistic matching, and will catch p=0.25 (in other
words: 25%) of the connections. The second rule catches p=0.33 (so, 33%)
of the *remaining* connections. The third rule catches p=0.50 (50%) of
the connections that remain after that. The last rule catches everything
that wasn't caught until then. That's it!

What now?

We have a one-node cluster, and it works, but:

- if we want to add more nodes, we need to setup kubelet to use a
  network plugin (CNI or otherwise), because for now, we are using
  the internal Docker bridge;
- as we add more nodes, we will need to make sure that the API server
  knows how to contact them, because by default it will try to use
  their names (which won't work unless you have a properly-set up
  local DNS server) and this problem will become apparent when
  using commands like `kubectl logs` or `kubectl exec`;
- we have no security and this is BAD: we need to set up TLS
  certificates;
- our control plane (etcd, API server, controller manager, scheduler)
  could be moved to containers and/or run as a set of non-root
  processes;
- that control plane could be made highly available;
- ideally, all these things should start automatically at boot
  (instead of manually in tmux!).

About that last item: it is possible to set up *only* kubelet
(and the container engine) to start automatically at boot
(e.g. with an appropriate systemd unit) and have everything else
started by containers in "static pods".

To be continued!



[etcd release page]: https://github.com/etcd-io/etcd/releases
[kubernetes release page]: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG-1.13.md#downloads-for-v1130

