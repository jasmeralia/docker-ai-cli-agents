# Jenkins Setup

This repository is designed to run from a Jenkins Pipeline job using the
checked-in [Jenkinsfile](/home/morgan/git/docker-ai-cli-agents/Jenkinsfile).

## Job Type

Use a Pipeline job configured as:

- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Script Path: `Jenkinsfile`

You can also use a Multibranch Pipeline if that matches your Jenkins
layout. The repository logic stays the same.

## Agent Requirements

The Jenkins agent that runs this job needs:

- `git`
- `make`
- `python3`
- `jq`
- Docker CLI access
- Permission to access `/var/run/docker.sock`

The version-detection flow calls:

- `make check-versions`
- `make update-versions`
- `git commit`
- `git tag`
- `git push`

`make check-versions` also runs the Claude version probe, which starts a
temporary `ubuntu:24.04` container and installs Claude inside it. That
means the Jenkins agent must be able to run `docker run` and pull images
when needed.

## Recommended Jenkins Container Setup

If Jenkins itself runs in Docker, use Docker Outside of Docker rather
than Docker-in-Docker:

- Mount `/var/run/docker.sock` into the Jenkins container.
- Ensure the Jenkins process can access the Docker socket.
- Install `git`, `make`, `python3`, `jq`, and Docker CLI in the Jenkins
  image or agent image.

Typical approaches:

- Run the Jenkins container as `root`.
- Match the host Docker group GID inside the container.
- Add the Jenkins user to a group that can access the Docker socket at
  startup.

## Repository Access

Configure the Git remote so Jenkins can push commits and tags back to
the repository.

Recommended options:

- SSH remote with an SSH credential that can push.
- HTTPS remote with a token that has repo write access.

The Pipeline uses these operations:

- `git push origin HEAD`
- `git push origin "v${RELEASE_VERSION}"`

If branch protections are enabled, make sure the Jenkins credential is
allowed to push the automated version bump commit and tag.

## Schedule

The schedule is already defined in [Jenkinsfile](/home/morgan/git/docker-ai-cli-agents/Jenkinsfile):

```groovy
cron('TZ=America/Los_Angeles\nH 4 1 * *')
```

That means Jenkins runs the job once per month at a hashed minute during
the 4:00 AM hour in the `America/Los_Angeles` timezone, on day `1` of
the month.

Do not duplicate the schedule in the Jenkins UI unless you explicitly
want a second trigger path.

## Pipeline Behavior

The job performs these stages:

1. `Checkout`
2. `Detect Versions`
3. `Update Versions`
4. `Commit And Tag`

The version logic is routed through the repo `Makefile`:

- `make check-versions`
- `make update-versions UPDATE_ARGS="..."`

If no upstream CLI version changed, the update and commit stages are
skipped.

## First-Run Checklist

Before enabling the scheduled trigger, verify:

1. The Jenkins agent can run `docker version`.
2. The agent can run `make check-versions` in a workspace checkout.
3. The agent can push a branch update to the repository remote.
4. The agent can create and push tags.

## Manual Validation

From a repository checkout on the Jenkins agent, these commands should
work:

```bash
make lint
make check-versions
make build IMAGE=docker-ai-cli-agents:test
make lint SMOKE_IMAGE=docker-ai-cli-agents:test
```

## Troubleshooting

Common failure points:

- `permission denied while trying to connect to the docker API`
  Cause: Jenkins cannot access `/var/run/docker.sock`.
- `make: command not found`
  Cause: the agent image is missing `make`.
- `jq: command not found`
  Cause: the agent image is missing `jq`.
- Git push or tag push fails
  Cause: Jenkins credentials or branch/tag permissions are incomplete.
- Claude probe fails during `make check-versions`
  Cause: the agent cannot pull/run Docker images or lacks outbound
  network access needed by the installer.
