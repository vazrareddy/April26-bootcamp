# Docker Exercises

Hands-on exercises based on the LivingDevOps Bootcamp session. Work through these in order — each one builds on the last.

---

## Prerequisites

Install Docker Desktop on your laptop (free for personal use). It installs all the required tooling automatically.

- Mac / Linux: [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
- Windows: Enable virtualisation in BIOS first, then install Docker Desktop
- Company laptop with no Docker license? Use **Podman** as a drop-in alternative (same commands, just replace `docker` with `podman`)

Verify your install:

```bash
docker --version
docker ps
```

---

## Exercise 1 — Pull and Run Your First Container

**Goal:** Understand what a container image is and how to run one.

```bash
# Run a busybox container (smallest Linux image ~6 MB)
docker run busybox

# Check running containers
docker ps

# Check ALL containers including exited ones
docker ps -a
```

**Questions to answer:**
- Why did the container exit immediately?
- What is the difference between `docker ps` and `docker ps -a`?

---

## Exercise 2 — Run an Interactive Container

**Goal:** Attach a shell to a running container and explore it like a Linux machine.

```bash
# Run busybox with a terminal attached (interactive mode)
docker run -it busybox sh

# Inside the container, try these commands
ls
pwd
ps -ef
whoami
hostname
exit
```

**Now try detached mode:**

```bash
# Run in background with -d flag, attach a terminal with -t
docker run -dt --name mybox busybox

# Verify it is running
docker ps

# Execute into the running container
docker exec -it mybox sh

# Inside container
ls
pwd
exit
```

**Questions to answer:**
- What is the difference between `docker run -it` and `docker run -dt` + `docker exec -it`?
- Why would you prefer the detached approach in a real workflow?

---

## Exercise 3 — Pull and Compare Image Sizes

**Goal:** Understand why image size matters and how to inspect images.

```bash
# Pull alpine Linux image (~13 MB)
docker pull alpine

# List all local images
docker images

# Compare sizes: busybox vs alpine vs a full Ubuntu image
docker pull ubuntu
docker images
```

**Questions to answer:**
- What is the size difference between busybox, alpine, and ubuntu?
- In production, why would you prefer a smaller base image?
- If a developer hands you a Dockerfile using `ubuntu` as the base for a Python app, what would you suggest instead?

---

## Exercise 4 — Container Lifecycle Management

**Goal:** Practice starting, stopping, and removing containers.

```bash
# Create two containers
docker run -dt --name box1 alpine
docker run -dt --name box2 busybox

# Check both are running
docker ps

# Stop one
docker stop box1

# Check status
docker ps -a

# Start it again
docker start box1

# Force remove a running container
docker rm -f box2

# Remove all stopped containers using shell substitution
docker rm -f $(docker ps -aq)

# Verify
docker ps -a
```

**Questions to answer:**
- What does `docker ps -aq` output? How is it used in the remove command?
- What is the difference between `docker stop` and `docker rm -f`?

---

## Exercise 5 — Inspect a Container

**Goal:** Understand what information lives inside a running container.

```bash
# Run a container
docker run -dt --name inspect-me alpine

# Inspect it
docker inspect inspect-me
```

Find the following in the output:

- Container ID
- IP address
- Gateway
- MAC address
- Log path (where logs are stored on the host)
- Network driver

```bash
# View container logs
docker logs inspect-me

# View resource usage (CPU, memory, network)
docker stats
# Press Ctrl+C to exit
```

**Questions to answer:**
- What does "host path" mean in the context of container storage?
- What IP was assigned to the container? What network is it using by default?

---

## Exercise 6 — Docker Networking (Default Bridge)

**Goal:** Understand how containers communicate on the default bridge network.

```bash
# Run two containers
docker run -dt --name net1 alpine
docker run -dt --name net2 busybox

# Get IP of net2
docker inspect net2 | grep IPAddress

# Go inside net1 and try to reach net2 by IP
docker exec -it net1 sh
ping <net2-IP>        # Should work
nslookup net2         # Will NOT work — no DNS on default bridge
exit
```

**Questions to answer:**
- Why does ping by IP work but `nslookup net2` fails?
- What network are both containers using by default?

---

## Exercise 7 — Custom Bridge Network with DNS

**Goal:** Enable container-to-container communication by name using a custom network.

```bash
# Create a custom network
docker network create mynetwork

# Run two containers on this custom network
docker run -dt --name app1 --network mynetwork alpine
docker run -dt --name app2 --network mynetwork busybox

# Go inside app1
docker exec -it app1 sh

# Try name resolution — this should work now
nslookup app2
ping app2
exit

# Inspect the network to confirm DNS registration
docker inspect mynetwork
```

**Questions to answer:**
- What changed between Exercise 6 and this exercise that made DNS work?
- Where do you see the container names registered in `docker inspect mynetwork`?

---

## Exercise 8 — Network Types Exploration

**Goal:** Understand none, host, and bridge network types.

```bash
# List all networks
docker network ls

# Run a container with NO network
docker run -dt --name isolated --network none alpine

# Inspect — notice there is no IP assigned
docker inspect isolated | grep IPAddress

# Try to exec in and ping anything
docker exec -it isolated sh
ping 8.8.8.8   # Should fail
exit

# Clean up
docker rm -f isolated
```

**Questions to answer:**
- When would you use `--network none` in a real scenario?
- What is the `host` network type used for? (Hint: it shares the host machine's network stack — useful in local testing, not recommended in production)

---

## Exercise 9 — Container Stats and Processes

**Goal:** Understand that containers are just processes on the host.

Open two terminals.

**Terminal 1:**
```bash
docker run -dt --name workload alpine
docker stats
```

**Terminal 2:**
```bash
# See docker-related processes on the host
ps -ef | grep docker

# You will see containerd, dockerd and the container processes
```

**Questions to answer:**
- How does `docker stats` relate to running `top` on a Linux machine?
- What is `containerd`? How does it relate to Docker?
- Kubernetes uses `containerd` directly — why does this mean Kubernetes does not need the full Docker daemon?

---

## Cleanup

Remove everything when done:

```bash
# Stop and remove all containers
docker rm -f $(docker ps -aq)

# Remove all images
docker rmi -f $(docker images -q)

# Remove custom networks
docker network prune
```

---

## Summary Checklist

Before the next class, make sure you can do the following without looking at notes:

- [ ] Run a container in interactive mode and in detached mode
- [ ] Exec into a running container
- [ ] Pull an image and check its size
- [ ] Start, stop, and force-remove containers
- [ ] Inspect a container and find its IP, MAC, and log path
- [ ] Explain why two containers on a default bridge cannot resolve each other by name
- [ ] Create a custom network and run containers on it with DNS working
- [ ] Explain the three default network types: none, host, bridge

---

## Coming Up Next Class

- Writing a Dockerfile from scratch
- Building your own container image
- Pushing an image to a registry (Docker Hub / ECR)
- Docker Compose — running multi-container apps (app + database)
- A real-world project simulating production setup
